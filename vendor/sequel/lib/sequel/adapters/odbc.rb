require 'odbc'

module Sequel
  module ODBC
    class Database < Sequel::Database
      set_adapter_scheme :odbc

      GUARDED_DRV_NAME = /^\{.+\}$/.freeze
      DRV_NAME_GUARDS = '{%s}'.freeze

      def initialize(opts)
        super(opts)
        case opts[:db_type]
        when 'mssql'
          Sequel.require 'adapters/odbc/mssql'
          extend Sequel::ODBC::MSSQL::DatabaseMethods
        when 'progress'
          Sequel.require 'adapters/shared/progress'
          extend Sequel::Progress::DatabaseMethods
        end
      end

      def connect(server)
        opts = server_opts(server)
        if opts.include? :driver
          drv = ::ODBC::Driver.new
          drv.name = 'Sequel ODBC Driver130'
          opts.each do |param, value|
            if :driver == param and not (value =~ GUARDED_DRV_NAME)
              value = DRV_NAME_GUARDS % value
            end
            drv.attrs[param.to_s.capitalize] = value
          end
          db = ::ODBC::Database.new
          conn = db.drvconnect(drv)
        else
          conn = ::ODBC::connect(opts[:database], opts[:user], opts[:password])
        end
        conn.autocommit = true
        conn
      end      

      def dataset(opts = nil)
        ODBC::Dataset.new(self, opts)
      end
    
      def execute(sql, opts={})
        log_info(sql)
        synchronize(opts[:server]) do |conn|
          begin
            r = conn.run(sql)
            yield(r) if block_given?
          rescue ::ODBC::Error => e
            raise_error(e)
          ensure
            r.drop if r
          end
          nil
        end
      end
      
      def execute_dui(sql, opts={})
        log_info(sql)
        synchronize(opts[:server]) do |conn|
          begin
            conn.do(sql)
          rescue ::ODBC::Error => e
            raise_error(e)
          end
        end
      end
      alias do execute_dui

      private
      
      def connection_pool_default_options
        super.merge(:pool_convert_exceptions=>false)
      end
      
      def connection_execute_method
        :do
      end

      def disconnect_connection(c)
        c.disconnect
      end
    end
    
    class Dataset < Sequel::Dataset
      BOOL_TRUE = '1'.freeze
      BOOL_FALSE = '0'.freeze
      ODBC_DATE_FORMAT = "{d '%Y-%m-%d'}".freeze
      TIMESTAMP_FORMAT="{ts '%Y-%m-%d %H:%M:%S'}".freeze

      def fetch_rows(sql, &block)
        execute(sql) do |s|
          i = -1
          cols = s.columns(true).map{|c| [output_identifier(c.name), i+=1]}
          @columns = cols.map{|c| c.at(0)}
          if rows = s.fetch_all
            rows.each do |row|
              hash = {}
              cols.each{|n,i| hash[n] = convert_odbc_value(row[i])}
              yield hash
            end
          end
        end
        self
      end
      
      private

      def convert_odbc_value(v)
        # When fetching a result set, the Ruby ODBC driver converts all ODBC 
        # SQL types to an equivalent Ruby type; with the exception of
        # SQL_TYPE_DATE, SQL_TYPE_TIME and SQL_TYPE_TIMESTAMP.
        #
        # The conversions below are consistent with the mappings in
        # ODBCColumn#mapSqlTypeToGenericType and Column#klass.
        case v
        when ::ODBC::TimeStamp
          Sequel.database_to_application_timestamp([v.year, v.month, v.day, v.hour, v.minute, v.second])
        when ::ODBC::Time
          Sequel.database_to_application_timestamp([now.year, now.month, now.day, v.hour, v.minute, v.second])
        when ::ODBC::Date
          Date.new(v.year, v.month, v.day)
        else
          v
        end
      end
      
      def default_timestamp_format
        TIMESTAMP_FORMAT
      end

      def literal_date(v)
        v.strftime(ODBC_DATE_FORMAT)
      end
      
      def literal_false
        BOOL_FALSE
      end
      
      def literal_true
        BOOL_TRUE
      end
    end
  end
end
