require_relative '03_associatable'

# Phase IV
module Associatable
  # Remember to go back to 04_associatable to write ::assoc_options

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
