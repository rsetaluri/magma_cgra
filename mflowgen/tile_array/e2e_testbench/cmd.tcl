###### heartbeat proc #######
proc heartbeat {} {
  set current_sim_time [time ns]
  puts "SIMULATION: Time is ${current_sim_time}"
}

# Save the session
save interconnect_chk -path sim_chk

##############
# Dump waves #
##############
if { $::env(waves) == "True" } {
  database -shm -default waves
  probe -shm Interconnect_tb -depth all -all
}

# Create heartbeat breakpoint for simulation monitoring...
stop -name heartbeat_bp -time -relative 1000 ns -execute heartbeat -continue -silent
# Jump ahead to flush assert to start saif...
stop -name flush_toggle -object Interconnect_tb.glb2io_1_X00_Y00
# run twice for the 0 then 1
run
run
stop -delete flush_toggle
# Print this time to config_duration.txt
set cfg_time [time ns]
#puts "$cfg_time" > config_duration.txt

##############
# Saif front #
##############
dumpsaif -scope Interconnect_tb -hierarchy -internal -output outputs/run.saif -overwrite

###########
# Runtime #
###########
run

# That run actually takes us to the end of the simulation...

############
# Saif end #
############
dumpsaif -end

# Print end time to app_duration.txt
set app_time [time ns]
#puts "$app_time" > app_duration.txt
#
quit