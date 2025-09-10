  def box_it(strings, bchar: "#")
    # Ensure we have an array of strings
    rows = Array(strings).map{|s| s.to_s.strip}
    max_width = rows.map(&:length).max || 0

    border = bchar * (max_width + 4)
    puts border
    rows.each do |s|
      puts "#{bchar} #{s.center(max_width)} #{bchar}"
    end
    puts border
  end
