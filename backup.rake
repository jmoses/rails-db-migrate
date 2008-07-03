# Original file by Tobias Luetke, found on
#   http://blog.leetsoft.com/2006/5/29/easy-migration-between-databases
#
# set_sequences task by tnb@thenakedbrain.com
#
# Updated for better ness (and put on github) by jon@burningbush.us
#   from source found at: http://ducktyped.com/2007/6/12/how-to-change-databases-using-ruby-on-rails
namespace :db do
  namespace :backup do
    
    def interesting_tables
      ActiveRecord::Base.connection.tables.sort.reject! do |tbl|
        ['schema_info', 'sessions', 'logged_exceptions'].include?(tbl)
      end
    end
    
    def change_yaml( str )
      str.gsub(/^--- \n/, '')
    end
  
    desc "Dump entire db."
    task :write => :environment do 
      require 'enumerator'


      dir = RAILS_ROOT + '/db/backup'
      FileUtils.mkdir_p(dir)
      FileUtils.chdir(dir)
    
      interesting_tables.each do |tbl|
        klass_name = tbl.classify
        
        ## Create class.
        eval("class #{klass_name} < ActiveRecord::Base ; end")

        klass = tbl.classify.constantize
        puts "Writing #{tbl}..."

        File.open("#{tbl}.yml", 'w+') do |f|
          if klass.column_names.include?("id")
            ids = ActiveRecord::Base.connection.select_values("select id from #{tbl}")
            ids.each_slice(1000) do |slice_of_ids|
              f << change_yaml(klass.find(:all, :conditions => ["id in (?)", slice_of_ids]).collect {|m| m.attributes }.to_yaml)
            end
          else
            YAML.dump klass.find(:all).collect {|a| a.attributes }, f
          end
        end
      end
    
    end

    task :read => [:environment, 'db:schema:load'] do 

      dir = RAILS_ROOT + '/db/backup'
      FileUtils.mkdir_p(dir)
      FileUtils.chdir(dir)
    
      interesting_tables.each do |tbl|
        klass_name = tbl.classify
        ## Create class.
        eval("class #{klass_name} < ActiveRecord::Base ; end")
        
        klass = tbl.classify.constantize
        ActiveRecord::Base.transaction do 
        
          puts "Loading #{tbl}..."
          YAML.load_file("#{tbl}.yml").each do |fixture|
            ActiveRecord::Base.connection.execute "INSERT INTO #{tbl} (#{fixture.keys.join(",")}) VALUES (#{fixture.values.collect { |value| ActiveRecord::Base.connection.quote(value) }.join(",")})", 'Fixture Insert'
          end        
        end
      end
    
    end

    desc "Set postgresql sequence currval to highest id for each table"
    task :set_sequences => :environment do
      if ActiveRecord::Base.connection.adapter_name.downcase == "postgresql"
        interesting_tables.each do |tbl|
          puts "Setting sequence's currval to highest id for #{tbl}"
          ActiveRecord::Base.connection.execute "select setval('#{tbl}_id_seq', (select max(id) from #{tbl}));"
        end
      else
        puts "This operation only works for postgresql databases."
      end
    end
  
  end
end