module Sequel
  # The offset of the current time zone from UTC, in seconds.
  LOCAL_DATETIME_OFFSET_SECS = Time.now.utc_offset
  
  # The offset of the current time zone from UTC, as a fraction of a day.
  LOCAL_DATETIME_OFFSET = respond_to?(:Rational, true) ? Rational(LOCAL_DATETIME_OFFSET_SECS, 60*60*24) : LOCAL_DATETIME_OFFSET_SECS/60/60/24.0
  
  @application_timezone = nil
  @database_timezone = nil
  @typecast_timezone = nil
  
  module Timezones
    attr_reader :application_timezone, :database_timezone, :typecast_timezone
  
    %w'application database typecast'.each do |t|
      class_eval("def #{t}_timezone=(tz); @#{t}_timezone = convert_timezone_setter_arg(tz) end", __FILE__, __LINE__)
    end
  
    # Convert the given Time/DateTime object into the database timezone, used when
    # literalizing objects in an SQL string.
    def application_to_database_timestamp(v)
      convert_output_timestamp(v, Sequel.database_timezone)
    end

    # Convert the given object into an object of Sequel.datetime_class in the
    # application_timezone.  Used when coverting datetime/timestamp columns
    # returned by the database.
    def database_to_application_timestamp(v)
      convert_timestamp(v, Sequel.database_timezone)
    end
  
    # Sets the database, application, and typecasting timezones to the given timezone. 
    def default_timezone=(tz)
      self.database_timezone = tz
      self.application_timezone = tz
      self.typecast_timezone = tz
    end
  
    # Convert the given object into an object of Sequel.datetime_class in the
    # application_timezone.  Used when typecasting values when assigning them
    # to model datetime attributes.
    def typecast_to_application_timestamp(v)
      convert_timestamp(v, Sequel.typecast_timezone)
    end

    private

    # Convert the given DateTime to the given input_timezone, keeping the
    # same time and just modifying the timezone.
    def convert_input_datetime_no_offset(v, input_timezone)
      case input_timezone
      when :utc
        v# DateTime assumes UTC if no offset is given
      when :local
        v.new_offset(LOCAL_DATETIME_OFFSET) - LOCAL_DATETIME_OFFSET
      else
        convert_input_datetime_other(v, input_timezone)
      end
    end
    
    # Convert the given DateTime to the given input_timezone that is not supported
    # by default (such as nil, :local, or :utc).  Raises an error by default.
    # Can be overridden in extensions.
    def convert_input_datetime_other(v, input_timezone)
      raise InvalidValue, "Invalid input_timezone: #{input_timezone.inspect}"
    end
    
    # Converts the object from a String, Array, Date, DateTime, or Time into an
    # instance of Sequel.datetime_class.  If given an array or a string that doesn't
    # contain an offset, assume that the array/string is already in the given input_timezone.
    def convert_input_timestamp(v, input_timezone)
      case v
      when String
        v2 = Sequel.string_to_datetime(v)
        if !input_timezone || Date._parse(v).has_key?(:offset)
          v2
        else
          # Correct for potentially wrong offset if string doesn't include offset
          if v2.is_a?(DateTime)
            v2 = convert_input_datetime_no_offset(v2, input_timezone)
          else
            # Time assumes local time if no offset is given
            v2 = v2.getutc + LOCAL_DATETIME_OFFSET_SECS if input_timezone == :utc
          end
          v2
        end
      when Array
        y, mo, d, h, mi, s = v
        if datetime_class == DateTime
          convert_input_datetime_no_offset(DateTime.civil(y, mo, d, h, mi, s, 0), input_timezone)
        else
          Time.send(input_timezone == :utc ? :utc : :local, y, mo, d, h, mi, s)
        end
      when Time
        if datetime_class == DateTime
          v.respond_to?(:to_datetime) ? v.to_datetime : string_to_datetime(v.iso8601)
        else
          v
        end
      when DateTime
        if datetime_class == DateTime
          v
        else
          v.respond_to?(:to_time) ? v.to_time : string_to_datetime(v.to_s)
        end
      when Date
        convert_input_timestamp(v.to_s, input_timezone)
      else
        raise InvalidValue, "Invalid convert_input_timestamp type: #{v.inspect}"
      end
    end
    
    # Convert the given DateTime to the given output_timezone that is not supported
    # by default (such as nil, :local, or :utc).  Raises an error by default.
    # Can be overridden in extensions.
    def convert_output_datetime_other(v, output_timezone)
      raise InvalidValue, "Invalid output_timezone: #{output_timezone.inspect}"
    end
    
    # Converts the object to the given output_timezone.
    def convert_output_timestamp(v, output_timezone)
      if output_timezone
        if v.is_a?(DateTime)
          case output_timezone
          when :utc
            v.new_offset(0)
          when :local
            v.new_offset(LOCAL_DATETIME_OFFSET)
          else
            convert_output_datetime_other(v, output_timezone)
          end
        else
          v.send(output_timezone == :utc ? :getutc : :getlocal)
        end
      else
        v
      end
    end
    
    # Converts the given object from the given input timezone to the
    # application timezone using convert_input_timestamp and
    # convert_output_timestamp.
    def convert_timestamp(v, input_timezone)
      begin
        convert_output_timestamp(convert_input_timestamp(v, input_timezone), Sequel.application_timezone)
      rescue InvalidValue
        raise
      rescue => e
        raise convert_exception_class(e, InvalidValue)
      end
    end
    
    # Convert the timezone setter argument.  Returns argument given by default,
    # exists for easier overriding in extensions.
    def convert_timezone_setter_arg(tz)
      tz
    end
  end

  extend Timezones
end
