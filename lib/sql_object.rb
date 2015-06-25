require_relative 'db_connection'
require 'active_support/inflector'
require 'byebug'
require 'pry'

class AssocOptions
  attr_accessor(
    :foreign_key,
    :class_name,
    :primary_key
  )

  def model_class
    class_name.constantize
  end

  def table_name
    model_class.table_name
  end
end

class BelongsToOptions < AssocOptions
  def initialize(name, options = {})
    @foreign_key = options[:foreign_key] || "#{name}_id".to_sym
    @primary_key = options[:primary_key] || :id
    @class_name  = options[:class_name]  || "#{name}".camelcase
  end
end

class HasManyOptions < AssocOptions
  def initialize(name, self_class_name, options = {})
    @foreign_key = options[:foreign_key] || "#{self_class_name}_id".underscore.to_sym
    @primary_key = options[:primary_key] || :id
    @class_name  = options[:class_name]  || "#{name}".camelcase.singularize
  end
end

module Associatable
  def belongs_to(name, options = {})
    assoc_options[name] = BelongsToOptions.new(name, options)
    options = assoc_options[name]
    define_method(name) do
      foreign_key = send(options.foreign_key)
      model_class = options.model_class
      model_class.where(options.primary_key => foreign_key).first
    end
  end

  def has_many(name, options = {})
    options = HasManyOptions.new(name, self.name, options)
    define_method(name) do
      primary_key = send(options.primary_key)
      model_class = options.model_class
      model_class.where(options.foreign_key => primary_key)
    end
  end

  def assoc_options
    @assoc_options ||= Hash.new
  end

  def has_one_through(name, through_name, source_name)
    through_options = assoc_options[through_name]
    define_method(name) do
      source_options = through_options.model_class.assoc_options[source_name]
      source_table = source_options.table_name
      source_params = DBConnection.execute(<<-SQL, send(through_options.foreign_key))
        SELECT
          #{source_options.table_name}.*
        FROM
          #{self.class.table_name}
        JOIN
          #{through_options.table_name}
          ON #{self.class.table_name}.#{through_options.foreign_key} =
             #{through_options.table_name}.#{through_options.primary_key}
        JOIN
          #{source_options.table_name}
          ON #{through_options.table_name}.#{source_options.foreign_key} =
            #{source_options.table_name}.#{source_options.primary_key}
        WHERE
            #{through_options.table_name}.#{through_options.primary_key} =
           ?
      SQL
      source_options.model_class.parse_all(source_params).first
    end
  end
end

class SQLObject
  extend Associatable

  def self.columns
    title = DBConnection.execute2(<<-SQL)
      SELECT
        *
      FROM
        #{table_name}
      LIMIT
        0
    SQL
    title.first.map(&:to_sym)
  end

  def self.finalize!
    columns.each do |col|
      define_method("#{col}") { attributes[col] }
      define_method("#{col}=") { |value| attributes[col] = value }
    end
  end

  def self.table_name=(table_name)
    @table_name = table_name
  end

  def self.table_name
    @table_name || self.to_s.tableize
  end

  def self.all
    all = DBConnection.execute(<<-SQL)
      SELECT
        *
      FROM
        #{table_name}
    SQL
    all.map do |hash|
      self.new(hash)
    end
  end

  def self.parse_all(results)
    results.map do |params|
      self.new(params)
    end
  end

  def self.find(id)
    object = DBConnection.execute(<<-SQL, id)
      SELECT
        *
      FROM
        #{table_name}
      WHERE
        id = ?
      LIMIT
        1
    SQL
    object.empty? ? nil : self.new(object.first)
  end

  def self.where(params)
    search = params.keys.map{|key| "#{key} = ?" }.join(' AND ')
    objects = DBConnection.execute(<<-SQL, params.values)
      SELECT
        *
      FROM
        #{self.table_name}
      WHERE
        #{search}
    SQL
    objects.map {|object| self.new(object)}
  end

  def initialize(params = {})
    params.each do |attr_name, value|
      if self.class.columns.include?(attr_name.to_sym)
        self.send("#{attr_name}=", value)
      else
        raise "unknown attribute '#{attr_name}'"
      end
    end
  end

  def attributes
    @attributes ||= Hash.new
  end

  def attribute_values
    @attributes.values
  end

  def insert
    col_names = @attributes.keys.join(',')
    question_marks = (['?'] * @attributes.keys.length).join(',')
    DBConnection.execute(<<-SQL, self.attribute_values)
      INSERT INTO
        #{self.class.table_name} (#{col_names})
      VALUES
        (#{question_marks})
    SQL
    self.id = DBConnection.last_insert_row_id
  end

  def update
    col_names = self.class.columns.map do |attr_name|
      "#{attr_name} = ?"
    end.join(', ')
    #debugger
    DBConnection.execute(<<-SQL, attribute_values, self.id)
      UPDATE
        #{self.class.table_name}
      SET
        #{col_names}
      WHERE
        id = ?
    SQL
  end

  def save
    self.id.nil? ? insert : update
  end
end
