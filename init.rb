# == MySql Migration Optimizer
# Extends the MySQL connector to provide:
# * Support for unsigned integer values through the +precision+ parameter
# * Support for column display width through the +scale+ parameter
# * Support for customization of the primary key value through +primary_column+ hash specified to +create_table+
#
# === UNSIGNED integers
# By default, use unsigned are used for integers (and booleans) unless
# <tt>:precision</tt> is set to <tt>:signed</tt> or globally configured
# by setting the +default_sign+ in environment.rb
#
#   MySqlMigrationOptimizer.default_sign = :signed
#
# Since foreign keys should match, it is a good idea to set the default
# to <tt>:signed</tt> if you have already established your app
#
#  add_column :giraffe, :beer_count, :integer, :precision => :signed
#  add_column :giraffe, :beer_count, :integer, :precision => :unsigned
#
#  create_table "giraffe" do |t|
#    t.integer "neck_length", :scale => 8, :precision => :signed
#    t.boolean "has_spots", :default => true
#  end
#
# Generated SQL:
#  CREATE TABLE `giraffe` (
#    `id` int(11) UNSIGNED NOT NULL auto_increment PRIMARY KEY,
#    `neck_length` int(8), `has_spots` tinyint(1) UNSIGNED DEFAULT 1
#  ) ENGINE=InnoDB
#
#
# === Integer Display width
# To set the integer display width, use <tt>:scale => XXX </tt>
# Display width is the max number of digits that MySQL will display and is not
# indicative of the storage size which is determined by the <tt>:limit</tt> option
#
#  add_column :giraffe, :beer_count, :integer, :scale => 8
#  SQL: ALTER TABLE `giraffe` ADD `beer_count` int(8) UNSIGNED
#
# Note that the type of integer tinyint, smallint, mediumint, int, and bigint
# are determined by the <tt>:limit</tt> from 1, 2, 3, 4, 5-8 respectively
# Therefore the following are equivalent
#
#  add_column :giraffe, :beer_count, :smallint
#  add_column :giraffe, :beer_count, :integer, :limit => 2
#
#  SQL: ALTER TABLE `giraffe` ADD `beer_count` smallint UNSIGNED
#
#
#
# In addition to the normal options of +create_table+,
# additional option of <tt>:primary_column</tt> can specify column attributes
# for the primary column. By default an unsigned int(11) is used
#
# === Create Table :primary_column Hash Map Options
# create_table allows for an additional map param <tt>:primary_column</tt> of options
# to define the primary key column.
#
# * <tt>:name</tt> - the same as specifying the <tt>:primary_key</tt> in the parent map
# * <tt>:scale</tt> - the scale of the variable
# * <tt>:precision</tt> - precision of the column. Set to <tt>:signed</tt> or <tt>:unsigned</tt> for integers and booleans. Defaults to the value of <tt>MySqlMigrationOptimizer.default_sign</tt> which is originaly set to <tt>:unsigned</tt>
# * <tt>:type</tt> - the type of column. Defaults to <tt>:integer</tt>
# * <tt>:null</tt> - set to false if the column is not nullable
# * <tt>:null</tt> - default value of the column
# * <tt>:auto_increment</tt> - Defaulted to true, set to false to turn off auto increment
#
# Specify a string column as the primary key
#  create_table "blah", :force => true,
#     :primary_column => {:type=>:string, :limit=>25, :auto_increment=>false}  do |t|#
#  end
#  SQL: CREATE TABLE `blah` (`id` varchar(25) NOT NULL PRIMARY KEY) ENGINE=InnoDB
#
# Specify the primary column as an unsigned (default) integer called special key
# with display width of 3
#  create_table "animal", :primary_key => "special_key", :force => true,
#   :primary_column => {:type=>:integer, :limit => 2, :scale=>3}  do |t|
#  end
#
#  SQL: CREATE TABLE `animal` (`special_key` smallint(3) UNSIGNED NOT NULL auto_increment PRIMARY KEY) ENGINE=InnoDB
#
#
# ==== Developers
# * Blythe Dunham http://snowgiraffe.com
#
# ==== Homepage
# * Homepage: http://www.snowgiraffe.com/tech/?tag=mysql_migration_optimizer
# * Rdoc: http://snowgiraffe.com/rdocs/mysql_migration_optimizer/index.html
# * GitHub Project: http://github.com/blythedunham/mysql_migration_optimizer/tree/master
# * Plugin Install: <tt>script/plugin git://github.com/blythedunham/mysql_migration_optimizer.git</tt>
#
# Copyright (c) 2009 Blythe Dunham, released under the MIT license

# Extends the MySqlColumn to extract scale and precision for generating
# schema.rb files
module MySqlMigrationOptimizerColumn
  def self.included(base)#:nodoc:
    %w(extract_precision extract_scale initialize).each {|method|
      base.send :alias_method_chain, method.to_sym, :mysql_options unless method_defined?("#{method}_without_mysql_options".to_sym)
    }
    base.send :attr_reader, :extras
  end

  # The new constructor with a values argument to pull in the extras info
  # This is used for auto_increment of primary_columns
  def initialize_with_mysql_options(name, default, sql_type = nil, null = true, extras = nil)#:nodoc:
    initialize_without_mysql_options(name, default, sql_type, null)
    @extras = extras
  end

  private
  def extract_precision_with_mysql_options(sql_type)#:nodoc:
   if sql_type =~ /^(big|tiny|medium|small)?int(.*(UNSIGNED))?/i
     precision = $3.blank? ? :signed : :unsigned
     return (precision == MySqlMigrationOptimizer.default_sign) ? nil : precision
   end
   extract_precision_without_mysql_options(sql_type)
  end

  def extract_scale_with_mysql_options(sql_type)#:nodoc:
    return ($2.to_i == 11 ? nil : $2.to_i) if sql_type =~ /^(big|tiny|medium|small)?int\((\d+)\)/i
    extract_scale_without_mysql_options(sql_type)
  end
end

# Extends the mysql connector to support unsigned integers, integer display width,
# and table creation options
module MySqlMigrationOptimizer

  #specify this attribute to indicate the default signage for integers (:unsigned or :signed)
  mattr_accessor :default_sign
  self.default_sign = :unsigned

  def self.included(base)#:nodoc:
    %w(native_database_types type_to_sql create_table).each {|method|
      base.send :alias_method_chain, method.to_sym, :mysql_options unless method_defined?("#{method}_without_mysql_options".to_sym)
    }
  end

  #Alias chain native_database_types
  def native_database_types_with_mysql_options#:nodoc:
    @@new_native_database_types ||= ActiveRecord::ConnectionAdapters::MysqlAdapter::NATIVE_DATABASE_TYPES.merge(:primary_key => default_primary_column_sql)
  end

  # Default SQL used with the primary column
  def default_primary_column_sql
    @@default_primary_column_sql ||= primary_column_sql
  end

  # Adds scale and precision SQL for integer types
  def type_to_sql_with_mysql_options(type, limit = nil, precision = nil, scale = nil)
    if (sql = type_to_sql_without_mysql_options(type, limit, precision, scale))
      sql = sql.to_s
      if type.to_s =~ /^(boolean|(big|tiny|medium|small)?int(eger)?)/
        add_integer_scale_and_precision!(sql, precision, scale)
      end
    end
    sql
  end

  # In addition to the normal options of +create_table+,
  # additional option of <tt>:primary_column</tt> can specify column attributes
  # for the primary column
  def create_table_with_mysql_options(table_name, options = {}, &block)#:nodoc:

    #temporarily assign primary_key to the column sql definition
    if (primary_column = options.delete(:primary_column))
      native_database_types[:primary_key] = primary_column_sql(primary_column)
      options[:primary_key]||= primary_column[:name] if primary_column[:name]
    end

    create_table_without_mysql_options(table_name, options, &block)

  #ensure that the type is reset if it was modified
  ensure
    @@new_native_database_types = nil if primary_column
  end

  # Similar to columns(table_name), this takes
  # * +table_name+ - name of the table
  # * +name+ - the query text
  # * +options+ - options[:conditions] can specify a where clause on the query
  #
  # This is only used to generate schema
  def columns_with_mysql_options(table_name, name = nil, options = {})
    sql = "SHOW FIELDS FROM #{quote_table_name(table_name)}"
    sql << " WHERE #{options[:conditions]} " if options[:conditions]
    columns = []
    result = execute(sql, name)
    result.each { |field| columns << ActiveRecord::ConnectionAdapters::MysqlColumn.new(field[0], field[4], field[1], field[2] == "YES", field[5]) }
    result.free
    columns
  end

  # Returns the <tt>:primary_columns</tt> options used when generating the
  # schema for +table_name+
  # If no <tt>:primary_columns</tt> are necessary, returns an empty hash
  def primary_column_schema_options(table_name)

    primary_column = columns_with_mysql_options(table_name, nil, :conditions => "`Key` = 'PRI'").first
    return '' if primary_column.nil?
    options = [:type, :limit, :null, :scale].inject({}) do |map, method|
      value = primary_column.send(method)
      map[method] = value if value
      map
    end

    options[:auto_increment] = false unless primary_column.extras.to_s.include?('auto_increment')

    primary_column_sql(options) != default_primary_column_sql ? options : {}

  end

  protected

  # Add the scale and precision (Unsigned or Signed) sql for integer fields
  def add_integer_scale_and_precision!(sql, precision, scale)
    if scale
      sql.gsub!(/\(\d+\)$/, '') #clear display width if already set
      sql << "(#{scale})"
    end
    
    sql << " UNSIGNED" if (precision||MySqlMigrationOptimizer.default_sign).to_s.downcase != 'signed'
    sql
  end

  # Generates the SQL used to generate the primary key column SQL in +create_table+
  def primary_column_sql(primary_column={})
    return primary_column if primary_column.is_a?(String)

    primary_column[:type]||= :integer
    #puts primary_column.inspect
    sql = type_to_sql(primary_column[:type], primary_column[:limit], primary_column[:precision], primary_column[:scale])
    sql << ' '
    add_primary_column_options!(sql, primary_column)
    sql
  end

  # Similar to <tt>add_column_options!</tt>, <tt>add_primary_column_options!</tt>
  # ads additional options for +auto_increment+ and PRIMARY KEY
  def add_primary_column_options!(sql, options={})
    add_column_options!(sql, options.reverse_merge(:null => false))
    sql << ' auto_increment' unless options[:auto_increment] == false
    sql << ' PRIMARY KEY'
    sql
  end
end



# Rewrite the table dumper to handle the +primary_column+ options
#
# Generate the table schema using the base and if the primary key
# does not match the default primary key, insert the correct hash map
# to +primary_column+ parameter of the +create_table+ options
module SchemaDumperWithMysqlOptions
   def self.included(base)#:nodoc:
    base.class_eval do
      private
      alias_method_chain :table, :mysql_options unless method_defined?(:table_without_mysql_options)
    end
  end

  # By using substitution we avoid rewriting the entire dumper
  def table_with_mysql_options(table_name, stream)#:nodoc:
    if (@connection.respond_to?(:primary_column_schema_options) &&
       (options = @connection.primary_column_schema_options(table_name)).any?)
      table_stream = StringIO.new
      table_without_mysql_options table_name, table_stream
      table_stream.rewind
      table_schema_txt = table_stream.read
      stream.print(schema_table_with_mysql_options(table_schema_txt, options))
    else
      table_without_mysql_options(table_name, stream)
    end
  end

  # Add the primary_column info into the table creation
  # For some reason, gsub with $1 has some issues, so use match instead
  def schema_table_with_mysql_options(txt, options={})#:nodoc:
    if match = txt.match(/create_table(.*)\s(do\s\|t\|)/)
      txt.gsub("create_table#{match[1]}", "create_table#{match[1]},\n   :primary_column => #{options.inspect} ")
    else
      txt
    end
  end
end


ActiveRecord::ConnectionAdapters::MysqlAdapter.send :include, MySqlMigrationOptimizer unless ActiveRecord::ConnectionAdapters::MysqlAdapter.respond_to?(:native_database_types_with_mysql_options)
ActiveRecord::ConnectionAdapters::MysqlColumn.send :include, MySqlMigrationOptimizerColumn unless ActiveRecord::ConnectionAdapters::MysqlColumn.respond_to?(:extract_scale_with_mysql_options)
ActiveRecord::SchemaDumper.send(:include, SchemaDumperWithMysqlOptions)
