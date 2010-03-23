require 'rubygems'
require 'sinatra'
require 'yaml'
require 'yaml/store'

enable :sessions
set :clean_trace, false

class Post
  COLUMNS = [:id, :name, :email, :content, :created_at]
  FILENAME = "sweet_words.yml"
  
  COLUMNS.each do |f| 
    define_method(f.to_s) { @attributes[f] }
  end
  
  class << self
    def all
      set = YAML::load_file(FILENAME)
      return [] unless set
      set.map {|i| self.load i.last}
    end
    
    def load(array)
      return nil if array.nil? || array.empty?
      hash = {}
      array.each_with_index do |value, index|
        hash[COLUMNS[index]] = value
      end
      Post.new(hash)
    end
    
    def new_id
      Time.now.to_i
    end
  end
  
  def initialize(attributes = {})
    @attributes = attributes
  end
  
  def id
    @attributes[:id] ||= self.class.new_id
  end
  
  def save
    YAML::Store.new(FILENAME).transaction do | store |
      store[self.class.name + '_' + self.id.to_s] = COLUMNS.map{|column| @attributes[column]}
    end
  end
end

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

before do 
  @flash = session["flash"] || {} 
  session["flash"] = nil 
end

helpers do
  def flash(args={}) 
    session["flash"] = args 
  end 
  
  def flash_now(args={}) 
    @flash = args 
  end
  
  def class_name_for(item, selected_item)
    selected_item == item ? 'selected' : ''
  end
  
  def link_to(name, url, options)
    "<a href=\"#{url}\" class=\"#{options[:class]}\">#{name}</a>"
  end
  
  def html_escape(s)
    s.to_s.gsub(/&/, "&amp;").gsub(/\"/, "&quot;").gsub(/>/, "&gt;").gsub(/</, "&lt;")
  end
  
  def newlines_and_links(s)
    newlines = s.gsub(/\n/, '<br>')
    links = newlines.gsub(/(http:\/\/[\w\/\.\-\d]+[\w\/\d\-])/, '<a href="\1">\1</a>')
  end
  
  def partial(page, options={})
    erb page, options.merge!(:layout => false)
  end
end

get '/' do
  @selected_item = :home
  erb :home
end

get '/nous-rejoindre' do
  @selected_item = :meet_us
  erb :meet_us
end

get '/ou-dormir' do
  @selected_item = :sleeping
  erb :sleeping
end

get '/chanter' do
  @selected_item = :sing
  erb :sing
end

get '/en-images' do
  @selected_item = :pictures
  erb :pictures
end

get '/mots-doux' do
  @posts = Post.all
  @post = Post.new
  @selected_item = :sweet_words
  erb :sweet_words
end

post '/mots-doux' do
  @post = Post.new(:name => html_escape(params[:post][:name]), 
                    :email => html_escape(params[:post][:scrambledmiale]), 
                    :content => html_escape(params[:post][:content]),
                    :created_at => Time.now)
                    
  if (!params[:post][:email].nil? && !params[:post][:email].empty? )
    flash(:error => "Il y a eu tentative de spam. Le message n'est pas enregistré.") 
  else
    if @post.name.empty? || @post.content.empty?
      @posts = Post.all
      flash_now(:error => "Vous devez au moins renseigner votre nom et un contenu pour enregistrer un message.") 
      return erb(:sweet_words)
    else
      @post.save
      flash(:notice => "Le message est bien enregistré, merci !") 
    end
  end
  redirect '/mots-doux'
end

get '/faire-un-cadeau' do
  @selected_item = :gifts
  erb :gifts
end

get '/questionnaire' do
  erb :questionnaire
end