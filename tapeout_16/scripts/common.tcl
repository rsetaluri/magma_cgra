# Common helper functions and variables to be used in multiple back-end scripts

##### PARAMETERS #####
# set x grid granularity to LCM of M3 and M5 and finfet pitches 
# (layers where we placed vertical pins)
set tile_x_grid 1.68 
# set y grid granularity to LCM of M4 and M6 pitches 
# (layers where we placed horizontal pins) and std_cell row height
set tile_y_grid 2.88

#stripe width
set tile_stripes(M7,width) 1
set tile_stripes(M8,width) 3
set tile_stripes(M9,width) 4
#stripe spacing
set tile_stripes(M7,spacing) 0.5
set tile_stripes(M8,spacing) 2
set tile_stripes(M9,spacing) 2
#stripe set to set distance
if $::env(PWR_AWARE) {
  set tile_stripes(M7,s2s) 10
  set tile_stripes(M8,s2s) 15
  set tile_stripes(M9,s2s) 20
} else {
set tile_stripes(M7,s2s) 10
set tile_stripes(M8,s2s) 12
set tile_stripes(M9,s2s) 16
}
#stripe start
set tile_stripes(M7,start) 2
set tile_stripes(M8,start) 4
set tile_stripes(M9,start) 4
##### END PARAMETERS #####


##### HELPER FUNCTIONS #####
proc snap_to_grid {input granularity edge_offset} {
   set new_value [expr (ceil(($input - $edge_offset)/$granularity) * $granularity) + $edge_offset]
   return $new_value
}

#proc macro_pg_blockage {macro margin} {
#   set llx [expr [get_property $macro x_coordinate_min]] 
#   set lly [expr [get_property $macro y_coordinate_min]] 
#   set urx [expr [get_property $macro x_coordinate_max]] 
#   set ury [expr [get_property $macro y_coordinate_max]]
#   set name [expr [get_property $macro hierarchical_name]]
#   #create_route_blockage -area {[expr $llx - $margin] $lly $llx $ury} -layers M1 -pg_nets
#   #create_route_blockage -area {$urx $lly [expr $urx + $margin] $ury} -layers M1 -pg_nets
#   create_route_blockage -inst $name -cover -pg_nets -layers M1 -spacing $margin 
#}

proc glbuf_sram_place {srams sram_start_x sram_start_y sram_spacing_x_even sram_spacing_x_odd sram_spacing_y bank_height sram_height sram_width} {
  set y_loc $sram_start_y
  set x_loc $sram_start_x
  set col 0
  set row 0
  foreach_in_collection sram $srams {
    set sram_name [get_property $sram full_name]
    set y_loc [snap_to_grid $y_loc 0.09 0]
    if {[expr $col % 2] == 0} {
      place_inst $sram_name $x_loc $y_loc -fixed MY
    } else {
      place_inst $sram_name $x_loc $y_loc -fixed
    }
    create_route_blockage -inst $sram_name -cover -pg_nets -layers M1 -spacing 2
    set row [expr $row + 1]
    set y_loc [expr $y_loc + $sram_height + $sram_spacing_y]
    # Next column over
    if {$row >= $bank_height} {
      set row 0
      set sram_spacing_x 0
      if {[expr $col % 2] == 0} {
        set sram_spacing_x $sram_spacing_x_even
      } else {
        set sram_spacing_x $sram_spacing_x_odd
      }
      set x_loc [expr $x_loc + $sram_width + $sram_spacing_x]
      set y_loc $sram_start_y
      set col [expr $col + 1]
    }
  }
}

proc get_cell_area_from_rpt {name} {
  # Parse post-synthesis area report to get cell area
  # Line starts with cell name
  set area_string [exec grep "^${name}" ../${name}/results_syn/final_area.rpt]
  # Split line on spaces
  set area_list [regexp -inline -all -- {\S+} $area_string]
  # Cell area is third word in string
  set cell_area [lindex $area_list 2]
}

proc get_tile_sizes {pe_util mem_util min_height min_width} {
  set pe_area [expr [get_cell_area_from_rpt Tile_PECore] / $pe_util]
  set mem_area [[get_cell_area_from_rpt Tile_MemCore] / $mem_util]
  # First make the smaller of the two tiles square
  set min_area $pe_area
  if {$pe_area > $mem_area} {
    set min_area $mem_area
  }
  set side_length [expr sqrt($min_area)]
  set height_1 $side_length
  set width_1 $side_length
  # Make sure this conforms to min_height
  set height_1 [expr max($height_1,$min_height)]
  set width_1 [expr $min_area
}

##### END HELPER FUNCTIONS #####
