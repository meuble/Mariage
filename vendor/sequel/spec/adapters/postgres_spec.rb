require File.join(File.dirname(__FILE__), 'spec_helper.rb')

unless defined?(POSTGRES_DB)
  POSTGRES_URL = 'postgres://postgres:postgres@localhost:5432/reality_spec' unless defined? POSTGRES_URL
  POSTGRES_DB = Sequel.connect(ENV['SEQUEL_PG_SPEC_DB']||POSTGRES_URL)
end
INTEGRATION_DB = POSTGRES_DB unless defined?(INTEGRATION_DB)

def POSTGRES_DB.sqls
  (@sqls ||= [])
end
logger = Object.new
def logger.method_missing(m, msg)
  POSTGRES_DB.sqls << msg
end
POSTGRES_DB.logger = logger

#POSTGRES_DB.instance_variable_set(:@server_version, 80100)
POSTGRES_DB.create_table! :test do
  text :name
  integer :value, :index => true
end
POSTGRES_DB.create_table! :test2 do
  text :name
  integer :value
end
POSTGRES_DB.create_table! :test3 do
  integer :value
  timestamp :time
end
POSTGRES_DB.create_table! :test4 do
  varchar :name, :size => 20
  bytea :value
end

context "A PostgreSQL database" do
  before do
    @db = POSTGRES_DB
  end
  
  specify "should provide the server version" do
    @db.server_version.should > 70000
  end

  specify "should correctly parse the schema" do
    @db.schema(:test3, :reload=>true).should == [
      [:value, {:type=>:integer, :allow_null=>true, :default=>nil, :ruby_default=>nil, :db_type=>"integer", :primary_key=>false}],
      [:time, {:type=>:datetime, :allow_null=>true, :default=>nil, :ruby_default=>nil, :db_type=>"timestamp without time zone", :primary_key=>false}]
    ]
    @db.schema(:test4, :reload=>true).should == [
      [:name, {:type=>:string, :allow_null=>true, :default=>nil, :ruby_default=>nil, :db_type=>"character varying(20)", :primary_key=>false}],
      [:value, {:type=>:blob, :allow_null=>true, :default=>nil, :ruby_default=>nil, :db_type=>"bytea", :primary_key=>false}]
    ]
  end
end

context "A PostgreSQL dataset" do
  before do
    @d = POSTGRES_DB[:test]
    @d.delete # remove all records
  end
  
  specify "should quote columns and tables using double quotes if quoting identifiers" do
    @d.quote_identifiers = true
    @d.select(:name).sql.should == \
      'SELECT "name" FROM "test"'
      
    @d.select('COUNT(*)'.lit).sql.should == \
      'SELECT COUNT(*) FROM "test"'

    @d.select(:max.sql_function(:value)).sql.should == \
      'SELECT max("value") FROM "test"'
      
    @d.select(:NOW.sql_function).sql.should == \
    'SELECT NOW() FROM "test"'

    @d.select(:max.sql_function(:items__value)).sql.should == \
      'SELECT max("items"."value") FROM "test"'

    @d.order(:name.desc).sql.should == \
      'SELECT * FROM "test" ORDER BY "name" DESC'

    @d.select('test.name AS item_name'.lit).sql.should == \
      'SELECT test.name AS item_name FROM "test"'
      
    @d.select('"name"'.lit).sql.should == \
      'SELECT "name" FROM "test"'

    @d.select('max(test."name") AS "max_name"'.lit).sql.should == \
      'SELECT max(test."name") AS "max_name" FROM "test"'
      
    @d.select(:test.sql_function(:abc, 'hello')).sql.should == \
      "SELECT test(\"abc\", 'hello') FROM \"test\""

    @d.select(:test.sql_function(:abc__def, 'hello')).sql.should == \
      "SELECT test(\"abc\".\"def\", 'hello') FROM \"test\""

    @d.select(:test.sql_function(:abc__def, 'hello').as(:x2)).sql.should == \
      "SELECT test(\"abc\".\"def\", 'hello') AS \"x2\" FROM \"test\""

    @d.insert_sql(:value => 333).should =~ \
      /\AINSERT INTO "test" \("value"\) VALUES \(333\)( RETURNING NULL)?\z/

    @d.insert_sql(:x => :y).should =~ \
      /\AINSERT INTO "test" \("x"\) VALUES \("y"\)( RETURNING NULL)?\z/

    @d.disable_insert_returning.insert_sql(:value => 333).should =~ \
      /\AINSERT INTO "test" \("value"\) VALUES \(333\)\z/
  end
  
  specify "should quote fields correctly when reversing the order if quoting identifiers" do
    @d.quote_identifiers = true
    @d.reverse_order(:name).sql.should == \
      'SELECT * FROM "test" ORDER BY "name" DESC'

    @d.reverse_order(:name.desc).sql.should == \
      'SELECT * FROM "test" ORDER BY "name" ASC'

    @d.reverse_order(:name, :test.desc).sql.should == \
      'SELECT * FROM "test" ORDER BY "name" DESC, "test" ASC'

    @d.reverse_order(:name.desc, :test).sql.should == \
      'SELECT * FROM "test" ORDER BY "name" ASC, "test" DESC'
  end

  specify "should support regexps" do
    @d << {:name => 'abc', :value => 1}
    @d << {:name => 'bcd', :value => 2}
    @d.filter(:name => /bc/).count.should == 2
    @d.filter(:name => /^bc/).count.should == 1
  end
  
  specify "should support for_share and for_update" do
    @d.for_share.all.should == []
    @d.for_update.all.should == []
  end
  
  specify "#lock should lock tables and yield if a block is given" do
    @d.lock('EXCLUSIVE'){@d.insert(:name=>'a')}
  end
  
  specify "#lock should lock table if inside a transaction" do
    POSTGRES_DB.transaction{@d.lock('EXCLUSIVE'); @d.insert(:name=>'a')}
  end
  
  specify "#lock should return nil" do
    @d.lock('EXCLUSIVE'){@d.insert(:name=>'a')}.should == nil
    POSTGRES_DB.transaction{@d.lock('EXCLUSIVE').should == nil; @d.insert(:name=>'a')}
  end
  
  specify "should raise an error if attempting to update a joined dataset with a single FROM table" do
    proc{POSTGRES_DB[:test].join(:test2, [:name]).update(:name=>'a')}.should raise_error(Sequel::Error, 'Need multiple FROM tables if updating/deleting a dataset with JOINs')
  end
end

context "A PostgreSQL dataset with a timestamp field" do
  before do
    @d = POSTGRES_DB[:test3]
    @d.delete
  end

  cspecify "should store milliseconds in time fields", :do do
    t = Time.now
    @d << {:value=>1, :time=>t}
    @d.literal(@d[:value =>'1'][:time]).should == @d.literal(t)
    @d[:value=>'1'][:time].usec.should == t.usec
  end
end

context "PostgreSQL's EXPLAIN and ANALYZE" do
  specify "should not raise errors" do
    @d = POSTGRES_DB[:test3]
    proc{@d.explain}.should_not raise_error
    proc{@d.analyze}.should_not raise_error
  end
end

context "A PostgreSQL database" do
  before do
    @db = POSTGRES_DB
  end

  specify "should support column operations" do
    @db.create_table!(:test2){text :name; integer :value}
    @db[:test2] << {}
    @db[:test2].columns.should == [:name, :value]

    @db.add_column :test2, :xyz, :text, :default => '000'
    @db[:test2].columns.should == [:name, :value, :xyz]
    @db[:test2] << {:name => 'mmm', :value => 111}
    @db[:test2].first[:xyz].should == '000'
  
    @db[:test2].columns.should == [:name, :value, :xyz]
    @db.drop_column :test2, :xyz
    
    @db[:test2].columns.should == [:name, :value]
  
    @db[:test2].delete
    @db.add_column :test2, :xyz, :text, :default => '000'
    @db[:test2] << {:name => 'mmm', :value => 111, :xyz => 'qqqq'}

    @db[:test2].columns.should == [:name, :value, :xyz]
    @db.rename_column :test2, :xyz, :zyx
    @db[:test2].columns.should == [:name, :value, :zyx]
    @db[:test2].first[:zyx].should == 'qqqq'
  
    @db.add_column :test2, :xyz, :float
    @db[:test2].delete
    @db[:test2] << {:name => 'mmm', :value => 111, :xyz => 56.78}
    @db.set_column_type :test2, :xyz, :integer
    
    @db[:test2].first[:xyz].should == 57
  end
  
  specify "#locks should be a dataset returning database locks " do
    @db.locks.should be_a_kind_of(Sequel::Dataset)
    @db.locks.all.should be_a_kind_of(Array)
  end
end  

context "A PostgreSQL database" do
  before do
    @db = POSTGRES_DB
    @db.drop_table(:posts) rescue nil
    @db.sqls.clear
  end
  after do
    @db.drop_table(:posts) rescue nil
  end
  
  specify "should support resetting the primary key sequence" do
    @db.create_table(:posts){primary_key :a}
    @db[:posts].insert(:a=>20).should == 20
    @db[:posts].insert.should == 1
    @db[:posts].insert.should == 2
    @db[:posts].insert(:a=>10).should == 10
    @db.reset_primary_key_sequence(:posts).should == 21
    @db[:posts].insert.should == 21
    @db[:posts].order(:a).map(:a).should == [1, 2, 10, 20, 21]
  end
  
  specify "should support specifying Integer/Bignum/Fixnum types in primary keys and have them be auto incrementing" do
    @db.create_table(:posts){primary_key :a, :type=>Integer}
    @db[:posts].insert.should == 1
    @db[:posts].insert.should == 2
    @db.create_table!(:posts){primary_key :a, :type=>Fixnum}
    @db[:posts].insert.should == 1
    @db[:posts].insert.should == 2
    @db.create_table!(:posts){primary_key :a, :type=>Bignum}
    @db[:posts].insert.should == 1
    @db[:posts].insert.should == 2
  end

  specify "should not raise an error if attempting to resetting the primary key sequence for a table without a primary key" do
    @db.create_table(:posts){Integer :a}
    @db.reset_primary_key_sequence(:posts).should == nil
  end
  
  specify "should support opclass specification" do
    @db.create_table(:posts){text :title; text :body; integer :user_id; index(:user_id, :opclass => :int4_ops, :type => :btree)}
    @db.sqls.should == [
    "CREATE TABLE posts (title text, body text, user_id integer)",
    "CREATE INDEX posts_user_id_index ON posts USING btree (user_id int4_ops)"
    ]
  end

  specify "should support fulltext indexes and searching" do
    @db.create_table(:posts){text :title; text :body; full_text_index [:title, :body]; full_text_index :title, :language => 'french'}
    @db.sqls.should == [
      "CREATE TABLE posts (title text, body text)",
      "CREATE INDEX posts_title_body_index ON posts USING gin (to_tsvector('simple', (COALESCE(title, '') || ' ' || COALESCE(body, ''))))",
      "CREATE INDEX posts_title_index ON posts USING gin (to_tsvector('french', (COALESCE(title, ''))))"
    ]

    @db[:posts].insert(:title=>'ruby rails', :body=>'yowsa')
    @db[:posts].insert(:title=>'sequel', :body=>'ruby')
    @db[:posts].insert(:title=>'ruby scooby', :body=>'x')
    @db.sqls.clear

    @db[:posts].full_text_search(:title, 'rails').all.should == [{:title=>'ruby rails', :body=>'yowsa'}]
    @db[:posts].full_text_search([:title, :body], ['yowsa', 'rails']).all.should == [:title=>'ruby rails', :body=>'yowsa']
    @db[:posts].full_text_search(:title, 'scooby', :language => 'french').all.should == [{:title=>'ruby scooby', :body=>'x'}]
    @db.sqls.should == [
      "SELECT * FROM posts WHERE (to_tsvector('simple', (COALESCE(title, ''))) @@ to_tsquery('simple', 'rails'))",
      "SELECT * FROM posts WHERE (to_tsvector('simple', (COALESCE(title, '') || ' ' || COALESCE(body, ''))) @@ to_tsquery('simple', 'yowsa | rails'))",
      "SELECT * FROM posts WHERE (to_tsvector('french', (COALESCE(title, ''))) @@ to_tsquery('french', 'scooby'))"]
  end

  specify "should support spatial indexes" do
    @db.create_table(:posts){box :geom; spatial_index [:geom]}
    @db.sqls.should == [
      "CREATE TABLE posts (geom box)",
      "CREATE INDEX posts_geom_index ON posts USING gist (geom)"
    ]
  end
  
  specify "should support indexes with index type" do
    @db.create_table(:posts){varchar :title, :size => 5; index :title, :type => 'hash'}
    @db.sqls.should == [
      "CREATE TABLE posts (title varchar(5))",
      "CREATE INDEX posts_title_index ON posts USING hash (title)"
    ]
  end
  
  specify "should support unique indexes with index type" do
    @db.create_table(:posts){varchar :title, :size => 5; index :title, :type => 'btree', :unique => true}
    @db.sqls.should == [
      "CREATE TABLE posts (title varchar(5))",
      "CREATE UNIQUE INDEX posts_title_index ON posts USING btree (title)"
    ]
  end
  
  specify "should support partial indexes" do
    @db.create_table(:posts){varchar :title, :size => 5; index :title, :where => {:title => '5'}}
    @db.sqls.should == [
      "CREATE TABLE posts (title varchar(5))",
      "CREATE INDEX posts_title_index ON posts (title) WHERE (title = '5')"
    ]
  end
  
  specify "should support identifiers for table names in indicies" do
    @db.create_table(Sequel::SQL::Identifier.new(:posts)){varchar :title, :size => 5; index :title, :where => {:title => '5'}}
    @db.sqls.should == [
      "CREATE TABLE posts (title varchar(5))",
      "CREATE INDEX posts_title_index ON posts (title) WHERE (title = '5')"
    ]
  end
  
  specify "should support renaming tables" do
    @db.create_table!(:posts1){primary_key :a}
    @db.rename_table(:posts1, :posts)
  end
end

context "Postgres::Dataset#import" do
  before do
    @db = POSTGRES_DB
    @db.create_table!(:test){Integer :x; Integer :y}
    @db.sqls.clear
    @ds = @db[:test]
  end
  after do
    @db.drop_table(:test) rescue nil
  end
  
  specify "#import should return separate insert statements if server_version < 80200" do
    @ds.meta_def(:server_version){80199}
    
    @ds.import([:x, :y], [[1, 2], [3, 4]])
    
    @db.sqls.should == [
      'BEGIN',
      'INSERT INTO test (x, y) VALUES (1, 2)',
      'INSERT INTO test (x, y) VALUES (3, 4)',
      'COMMIT'
    ]
    @ds.all.should == [{:x=>1, :y=>2}, {:x=>3, :y=>4}]
  end
  
  specify "#import should a single insert statement if server_version >= 80200" do
    @ds.meta_def(:server_version){80200}
    
    @ds.import([:x, :y], [[1, 2], [3, 4]])
    
    @db.sqls.should == [
      'BEGIN',
      'INSERT INTO test (x, y) VALUES (1, 2), (3, 4)',
      'COMMIT'
    ]
    @ds.all.should == [{:x=>1, :y=>2}, {:x=>3, :y=>4}]
  end
end

context "Postgres::Dataset#insert" do
  before do
    @db = POSTGRES_DB
    @db.create_table!(:test5){primary_key :xid; Integer :value}
    @db.sqls.clear
    @ds = @db[:test5]
  end
  after do
    @db.drop_table(:test5) rescue nil
  end

  specify "should work with static SQL" do
    @ds.with_sql('INSERT INTO test5 (value) VALUES (10)').insert.should == nil
    @db['INSERT INTO test5 (value) VALUES (20)'].insert.should == nil
    @ds.all.should == [{:xid=>1, :value=>10}, {:xid=>2, :value=>20}]
  end

  specify "should work regardless of how it is used" do
    @ds.insert(:value=>10).should == 1
    @ds.disable_insert_returning.insert(:value=>20).should == 2
    @ds.meta_def(:server_version){80100}
    @ds.insert(:value=>13).should == 3
    
    @db.sqls.reject{|x| x =~ /pg_class/}.should == [
      'INSERT INTO test5 (value) VALUES (10) RETURNING xid',
      'INSERT INTO test5 (value) VALUES (20)',
      "SELECT currval('\"public\".test5_xid_seq')",
      'INSERT INTO test5 (value) VALUES (13)',
      "SELECT currval('\"public\".test5_xid_seq')"
    ]
    @ds.all.should == [{:xid=>1, :value=>10}, {:xid=>2, :value=>20}, {:xid=>3, :value=>13}]
  end
  
  specify "should call execute_insert if server_version < 80200" do
    @ds.meta_def(:server_version){80100}
    @ds.should_receive(:execute_insert).once.with('INSERT INTO test5 (value) VALUES (10)', :table=>:test5, :values=>{:value=>10})
    @ds.insert(:value=>10)
  end

  specify "should call execute_insert if disabling insert returning" do
    @ds.disable_insert_returning!
    @ds.should_receive(:execute_insert).once.with('INSERT INTO test5 (value) VALUES (10)', :table=>:test5, :values=>{:value=>10})
    @ds.insert(:value=>10)
  end

  specify "should use INSERT RETURNING if server_version >= 80200" do
    @ds.meta_def(:server_version){80201}
    @ds.insert(:value=>10)
    @db.sqls.last.should == 'INSERT INTO test5 (value) VALUES (10) RETURNING xid'
  end

  specify "should have insert_returning_sql use the RETURNING keyword" do
    @ds.insert_returning_sql(:xid, :value=>10).should == "INSERT INTO test5 (value) VALUES (10) RETURNING xid"
    @ds.insert_returning_sql('*'.lit, :value=>10).should == "INSERT INTO test5 (value) VALUES (10) RETURNING *"
  end

  specify "should have insert_select return nil if server_version < 80200" do
    @ds.meta_def(:server_version){80100}
    @ds.insert_select(:value=>10).should == nil
  end

  specify "should have insert_select return nil if disable_insert_returning is used" do
    @ds.disable_insert_returning.insert_select(:value=>10).should == nil
  end

  specify "should have insert_select insert the record and return the inserted record if server_version >= 80200" do
    @ds.meta_def(:server_version){80201}
    h = @ds.insert_select(:value=>10)
    h[:value].should == 10
    @ds.first(:xid=>h[:xid])[:value].should == 10
  end

  specify "should correctly return the inserted record's primary key value" do
    value1 = 10
    id1 = @ds.insert(:value=>value1)
    @ds.first(:xid=>id1)[:value].should == value1
    value2 = 20
    id2 = @ds.insert(:value=>value2)
    @ds.first(:xid=>id2)[:value].should == value2
  end

  specify "should return nil if the table has no primary key" do
    ds = POSTGRES_DB[:test4]
    ds.delete
    ds.insert(:name=>'a').should == nil
  end
end

context "Postgres::Database schema qualified tables" do
  before do
    POSTGRES_DB << "CREATE SCHEMA schema_test"
    POSTGRES_DB.instance_variable_set(:@primary_keys, {})
    POSTGRES_DB.instance_variable_set(:@primary_key_sequences, {})
  end
  after do
    POSTGRES_DB.quote_identifiers = false
    POSTGRES_DB << "DROP SCHEMA schema_test CASCADE"
    POSTGRES_DB.default_schema = :public
  end
  
  specify "should be able to create, drop, select and insert into tables in a given schema" do
    POSTGRES_DB.create_table(:schema_test__schema_test){primary_key :i}
    POSTGRES_DB[:schema_test__schema_test].first.should == nil
    POSTGRES_DB[:schema_test__schema_test].insert(:i=>1).should == 1
    POSTGRES_DB[:schema_test__schema_test].first.should == {:i=>1}
    POSTGRES_DB.from('schema_test.schema_test'.lit).first.should == {:i=>1}
    POSTGRES_DB.drop_table(:schema_test__schema_test)
    POSTGRES_DB.create_table(:schema_test.qualify(:schema_test)){integer :i}
    POSTGRES_DB[:schema_test__schema_test].first.should == nil
    POSTGRES_DB.from('schema_test.schema_test'.lit).first.should == nil
    POSTGRES_DB.drop_table(:schema_test.qualify(:schema_test))
  end
  
  specify "#tables should include only tables in the public schema if no schema is given" do
    POSTGRES_DB.create_table(:schema_test__schema_test){integer :i}
    POSTGRES_DB.tables.should_not include(:schema_test)
  end
  
  specify "#tables should return tables in the schema provided by the :schema argument" do
    POSTGRES_DB.create_table(:schema_test__schema_test){integer :i}
    POSTGRES_DB.tables(:schema=>:schema_test).should == [:schema_test]
  end
  
  specify "#table_exists? should assume the public schema if no schema is provided" do
    POSTGRES_DB.create_table(:schema_test__schema_test){integer :i}
    POSTGRES_DB.table_exists?(:schema_test).should == false
  end
  
  specify "#table_exists? should see if the table is in a given schema" do
    POSTGRES_DB.create_table(:schema_test__schema_test){integer :i}
    POSTGRES_DB.table_exists?(:schema_test__schema_test).should == true
  end
  
  specify "should be able to get primary keys for tables in a given schema" do
    POSTGRES_DB.create_table(:schema_test__schema_test){primary_key :i}
    POSTGRES_DB.primary_key(:schema_test__schema_test).should == 'i'
  end
  
  specify "should be able to get serial sequences for tables in a given schema" do
    POSTGRES_DB.create_table(:schema_test__schema_test){primary_key :i}
    POSTGRES_DB.primary_key_sequence(:schema_test__schema_test).should == '"schema_test".schema_test_i_seq'
  end
  
  specify "should be able to get serial sequences for tables that have spaces in the name in a given schema" do
    POSTGRES_DB.quote_identifiers = true
    POSTGRES_DB.create_table(:"schema_test__schema test"){primary_key :i}
    POSTGRES_DB.primary_key_sequence(:"schema_test__schema test").should == '"schema_test"."schema test_i_seq"'
  end
  
  specify "should be able to get custom sequences for tables in a given schema" do
    POSTGRES_DB << "CREATE SEQUENCE schema_test.kseq"
    POSTGRES_DB.create_table(:schema_test__schema_test){integer :j; primary_key :k, :type=>:integer, :default=>"nextval('schema_test.kseq'::regclass)".lit}
    POSTGRES_DB.primary_key_sequence(:schema_test__schema_test).should == '"schema_test".kseq'
  end
  
  specify "should be able to get custom sequences for tables that have spaces in the name in a given schema" do
    POSTGRES_DB.quote_identifiers = true
    POSTGRES_DB << "CREATE SEQUENCE schema_test.\"ks eq\""
    POSTGRES_DB.create_table(:"schema_test__schema test"){integer :j; primary_key :k, :type=>:integer, :default=>"nextval('schema_test.\"ks eq\"'::regclass)".lit}
    POSTGRES_DB.primary_key_sequence(:"schema_test__schema test").should == '"schema_test"."ks eq"'
  end
  
  specify "#default_schema= should change the default schema used from public" do
    POSTGRES_DB.create_table(:schema_test__schema_test){primary_key :i}
    POSTGRES_DB.default_schema = :schema_test
    POSTGRES_DB.table_exists?(:schema_test).should == true
    POSTGRES_DB.tables.should == [:schema_test]
    POSTGRES_DB.primary_key(:schema_test__schema_test).should == 'i'
    POSTGRES_DB.primary_key_sequence(:schema_test__schema_test).should == '"schema_test".schema_test_i_seq'
  end
end

if POSTGRES_DB.server_version >= 80300

  POSTGRES_DB.create_table! :test6 do
    text :title
    text :body
    full_text_index [:title, :body]
  end

  context "PostgreSQL tsearch2" do
    before do
      @ds = POSTGRES_DB[:test6]
    end
    after do
      POSTGRES_DB[:test6].delete
    end

    specify "should search by indexed column" do
      record =  {:title => "oopsla conference", :body => "test"}
      @ds << record
      @ds.full_text_search(:title, "oopsla").all.should include(record)
    end

    specify "should join multiple coumns with spaces to search by last words in row" do
      record = {:title => "multiple words", :body => "are easy to search"}
      @ds << record
      @ds.full_text_search([:title, :body], "words").all.should include(record)
    end

    specify "should return rows with a NULL in one column if a match in another column" do
      record = {:title => "multiple words", :body =>nil}
      @ds << record
      @ds.full_text_search([:title, :body], "words").all.should include(record)
    end
  end
end

if POSTGRES_DB.dataset.supports_window_functions?
  context "Postgres::Dataset named windows" do
    before do
      @db = POSTGRES_DB
      @db.create_table!(:i1){Integer :id; Integer :group_id; Integer :amount}
      @ds = @db[:i1].order(:id)
      @ds.insert(:id=>1, :group_id=>1, :amount=>1)
      @ds.insert(:id=>2, :group_id=>1, :amount=>10)
      @ds.insert(:id=>3, :group_id=>1, :amount=>100)
      @ds.insert(:id=>4, :group_id=>2, :amount=>1000)
      @ds.insert(:id=>5, :group_id=>2, :amount=>10000)
      @ds.insert(:id=>6, :group_id=>2, :amount=>100000)
    end
    after do
      @db.drop_table(:i1)
    end
    
    specify "should give correct results for window functions" do
      @ds.window(:win, :partition=>:group_id, :order=>:id).select(:id){sum(:over, :args=>amount, :window=>win){}}.all.should ==
        [{:sum=>1, :id=>1}, {:sum=>11, :id=>2}, {:sum=>111, :id=>3}, {:sum=>1000, :id=>4}, {:sum=>11000, :id=>5}, {:sum=>111000, :id=>6}]
      @ds.window(:win, :partition=>:group_id).select(:id){sum(:over, :args=>amount, :window=>win, :order=>id){}}.all.should ==
        [{:sum=>1, :id=>1}, {:sum=>11, :id=>2}, {:sum=>111, :id=>3}, {:sum=>1000, :id=>4}, {:sum=>11000, :id=>5}, {:sum=>111000, :id=>6}]
      @ds.window(:win, {}).select(:id){sum(:over, :args=>amount, :window=>:win, :order=>id){}}.all.should ==
        [{:sum=>1, :id=>1}, {:sum=>11, :id=>2}, {:sum=>111, :id=>3}, {:sum=>1111, :id=>4}, {:sum=>11111, :id=>5}, {:sum=>111111, :id=>6}]
      @ds.window(:win, :partition=>:group_id).select(:id){sum(:over, :args=>amount, :window=>:win, :order=>id, :frame=>:all){}}.all.should ==
        [{:sum=>111, :id=>1}, {:sum=>111, :id=>2}, {:sum=>111, :id=>3}, {:sum=>111000, :id=>4}, {:sum=>111000, :id=>5}, {:sum=>111000, :id=>6}]
    end
  end
end

context "Postgres::Database functions, languages, and triggers" do
  before do
    @d = POSTGRES_DB
  end
  after do
    @d.drop_function('tf', :if_exists=>true, :cascade=>true)
    @d.drop_function('tf', :if_exists=>true, :cascade=>true, :args=>%w'integer integer')
    @d.drop_language(:plpgsql, :if_exists=>true, :cascade=>true)
    @d.drop_table(:test) rescue nil
  end

  specify "#create_function and #drop_function should create and drop functions" do
    proc{@d['SELECT tf()'].all}.should raise_error(Sequel::DatabaseError)
    args = ['tf', 'SELECT 1', {:returns=>:integer}]
    @d.send(:create_function_sql, *args).should =~ /\A\s*CREATE FUNCTION tf\(\)\s+RETURNS integer\s+LANGUAGE SQL\s+AS 'SELECT 1'\s*\z/
    @d.create_function(*args)
    rows = @d['SELECT tf()'].all.should == [{:tf=>1}]
    @d.send(:drop_function_sql, 'tf').should == 'DROP FUNCTION tf()'
    @d.drop_function('tf')
    proc{@d['SELECT tf()'].all}.should raise_error(Sequel::DatabaseError)
  end
  
  specify "#create_function and #drop_function should support options" do
    args = ['tf', 'SELECT $1 + $2', {:args=>[[:integer, :a], :integer], :replace=>true, :returns=>:integer, :language=>'SQL', :behavior=>:immutable, :strict=>true, :security_definer=>true, :cost=>2, :set=>{:search_path => 'public'}}]
    @d.send(:create_function_sql,*args).should =~ /\A\s*CREATE OR REPLACE FUNCTION tf\(a integer, integer\)\s+RETURNS integer\s+LANGUAGE SQL\s+IMMUTABLE\s+STRICT\s+SECURITY DEFINER\s+COST 2\s+SET search_path = public\s+AS 'SELECT \$1 \+ \$2'\s*\z/
    @d.create_function(*args)
    # Make sure replace works
    @d.create_function(*args)
    rows = @d['SELECT tf(1, 2)'].all.should == [{:tf=>3}]
    args = ['tf', {:if_exists=>true, :cascade=>true, :args=>[[:integer, :a], :integer]}]
    @d.send(:drop_function_sql,*args).should == 'DROP FUNCTION IF EXISTS tf(a integer, integer) CASCADE'
    @d.drop_function(*args)
    # Make sure if exists works
    @d.drop_function(*args)
  end
  
  specify "#create_language and #drop_language should create and drop languages" do
    @d.send(:create_language_sql, :plpgsql).should == 'CREATE LANGUAGE plpgsql'
    @d.create_language(:plpgsql)
    proc{@d.create_language(:plpgsql)}.should raise_error(Sequel::DatabaseError)
    @d.send(:drop_language_sql, :plpgsql).should == 'DROP LANGUAGE plpgsql'
    @d.drop_language(:plpgsql)
    proc{@d.drop_language(:plpgsql)}.should raise_error(Sequel::DatabaseError)
    @d.send(:create_language_sql, :plpgsql, :trusted=>true, :handler=>:a, :validator=>:b).should == 'CREATE TRUSTED LANGUAGE plpgsql HANDLER a VALIDATOR b'
    @d.send(:drop_language_sql, :plpgsql, :if_exists=>true, :cascade=>true).should == 'DROP LANGUAGE IF EXISTS plpgsql CASCADE'
    # Make sure if exists works
    @d.drop_language(:plpgsql, :if_exists=>true, :cascade=>true)
  end
  
  specify "#create_trigger and #drop_trigger should create and drop triggers" do
    @d.create_language(:plpgsql)
    @d.create_function(:tf, 'BEGIN IF NEW.value IS NULL THEN RAISE EXCEPTION \'Blah\'; END IF; RETURN NEW; END;', :language=>:plpgsql, :returns=>:trigger)
    @d.send(:create_trigger_sql, :test, :identity, :tf, :each_row=>true).should == 'CREATE TRIGGER identity BEFORE INSERT OR UPDATE OR DELETE ON public.test FOR EACH ROW EXECUTE PROCEDURE tf()'
    @d.create_table(:test){String :name; Integer :value}
    @d.create_trigger(:test, :identity, :tf, :each_row=>true)
    @d[:test].insert(:name=>'a', :value=>1)
    @d[:test].filter(:name=>'a').all.should == [{:name=>'a', :value=>1}]
    proc{@d[:test].filter(:name=>'a').update(:value=>nil)}.should raise_error(Sequel::DatabaseError)
    @d[:test].filter(:name=>'a').all.should == [{:name=>'a', :value=>1}]
    @d[:test].filter(:name=>'a').update(:value=>3)
    @d[:test].filter(:name=>'a').all.should == [{:name=>'a', :value=>3}]
    @d.send(:drop_trigger_sql, :test, :identity).should == 'DROP TRIGGER identity ON public.test'
    @d.drop_trigger(:test, :identity)
    @d.send(:create_trigger_sql, :test, :identity, :tf, :after=>true, :events=>:insert, :args=>[1, 'a']).should == 'CREATE TRIGGER identity AFTER INSERT ON public.test EXECUTE PROCEDURE tf(1, \'a\')'
    @d.send(:drop_trigger_sql, :test, :identity, :if_exists=>true, :cascade=>true).should == 'DROP TRIGGER IF EXISTS identity ON public.test CASCADE'
    # Make sure if exists works
    @d.drop_trigger(:test, :identity, :if_exists=>true, :cascade=>true)
  end
end

if POSTGRES_DB.class.adapter_scheme == :postgres
context "Postgres::Dataset #use_cursor" do
  before(:all) do
    @db = POSTGRES_DB
    @db.create_table!(:test_cursor){Integer :x}
    @db.sqls.clear
    @ds = @db[:test_cursor]
    @db.transaction{1001.times{|i| @ds.insert(i)}}
  end
  after(:all) do
    @db.drop_table(:test) rescue nil
  end
  
    specify "should return the same results as the non-cursor use" do
      @ds.all.should == @ds.use_cursor.all
    end
    
    specify "should respect the :rows_per_fetch option" do
      @db.sqls.clear
      @ds.use_cursor.all
      @db.sqls.length.should == 6
      @db.sqls.clear
      @ds.use_cursor(:rows_per_fetch=>100).all
      @db.sqls.length.should == 15
    end
    
    specify "should handle returning inside block" do
      def @ds.check_return
        use_cursor.each{|r| return}
      end
      @ds.check_return
      @ds.all.should == @ds.use_cursor.all
    end
end
end
