
You: write some ruby code for me:  I want a method that takes an Array of left justified Strings an
d centers each entry based upon the longest entry then outputs these strings to stdout enclosed within a box made
out of the ascii character for pound sign.

AI: 
   def boxed_center(strings)
     # Ensure we have an array of strings
     rows = Array(strings).map(&:to_s)
     max_width = rows.map(&:length).max || 0
   
     border = "#" * (max_width + 4)
     puts border
     rows.each do |s|
       puts "# #{s.center(max_width)} #"
     end
     puts border
   end
   
   # Example:
   # boxed_center(["alpha", "beta", "gamma rays", "delta"])
   # Output:
   # ##############
   # #   alpha    #
   # #    beta    #
   # # gamma rays #
   # #   delta    #
   # ##############
