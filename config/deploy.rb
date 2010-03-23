load 'deploy' if respond_to?(:namespace) # cap2 differentiator

default_run_options[:pty] = true

# be sure to change these
set :user, 'michel'
set :domain, 'mariage.claireetmichel.com'
set :application, 'mariage'

# the rest should be good
set :repository,  "git://github.com/meuble/Mariage.git" 
set :deploy_to, "/home/#{user}/#{domain}"
set :deploy_via, :remote_cache
set :scm, 'git'
set :branch, 'master'
set :git_shallow_clone, 1
set :scm_verbose, true
set :use_sudo, false

server domain, :app, :web

namespace :deploy do
  task :restart do
    run "touch #{current_path}/tmp/restart.txt" 
  end
end

after 'deploy:update_code', 'shared_links:symlink'

namespace :shared_links do
  task :symlink do
    run "ln -nfs #{shared_path}/system/sweet_words.yml #{release_path}/sweet_words.yml"
  end
end