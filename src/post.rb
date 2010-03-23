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