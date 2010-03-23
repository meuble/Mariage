class Date
  alias :strftime_nolocale :strftime

    FR_ABBR_DAYNAMES = %w(Dim Lun Mar Mer Jeu Ven Sam)
    FR_MONTHNAMES =  [
      nil, "janvier", "février", "mars", "avril", "mai", "juin", "juillet", "août", "septembre", "octobre", "novembre", "décembre"]
    FR_ABBR_MONTHNAMES =  [
      nil, "jan", "fév", "mar", "avr", "mai", "jun", "jui", "aoû", "sep", "oct", "nov", "déc"]
    FR_DAYNAMES = %w(dimanche lundi mardi mercredi jeudi vendredi samedi)    

  def strftime(format)
    format = format.dup
    format.gsub!(/%a/, Date::FR_ABBR_DAYNAMES[self.wday])
    format.gsub!(/%A/, Date::FR_DAYNAMES[self.wday])
    format.gsub!(/%b/, Date::FR_ABBR_MONTHNAMES[self.mon])
    format.gsub!(/%B/, Date::FR_MONTHNAMES[self.mon])
    self.strftime_nolocale(format)
  end
end

class Time
  alias :strftime_nolocale :strftime

  def strftime(format)
    format = format.dup
    format.gsub!(/%a/, Date::FR_ABBR_DAYNAMES[self.wday])
    format.gsub!(/%A/, Date::FR_DAYNAMES[self.wday])
    format.gsub!(/%b/, Date::FR_ABBR_MONTHNAMES[self.mon])
    format.gsub!(/%B/, Date::FR_MONTHNAMES[self.mon])
    self.strftime_nolocale(format)
  end
end