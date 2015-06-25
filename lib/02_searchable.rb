require_relative 'db_connection'
require_relative '01_sql_object'

module Searchable
  def where(params)
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
end

class SQLObject
  extend Searchable
  # Mixin Searchable here...
end
