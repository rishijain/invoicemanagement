# Puma configuration for production (single process mode)                                                                                                           
                                                                                                                                                                      
max_threads_count = ENV.fetch("RAILS_MAX_THREADS") { 5 }                                                                                                            
min_threads_count = ENV.fetch("RAILS_MIN_THREADS") { max_threads_count }                                                                                            
threads min_threads_count, max_threads_count                                                                                                                        
                                                                                                                                                                      
# Bind to all interfaces on port 3000                                                                                                                               
bind "tcp://0.0.0.0:3000"                                                                                                                                           
                                                                                                                                                                      
environment ENV.fetch("RAILS_ENV") { "production" }                                                                                                                 
                                                                                                                                                                      
pidfile ENV.fetch("PIDFILE") { "tmp/pids/puma.pid" }                                                                                                                
                                                                                                                                                                      
plugin :tmp_restart           
