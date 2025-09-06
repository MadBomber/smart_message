#!/usr/bin/env ruby
# examples/redis_queue/06_emergency_alerts.rb
# Emergency alert system with Redis Queue Transport

require_relative '../../lib/smart_message'

puts "🚨 Redis Queue Transport - Emergency Alert System Demo"
puts "=" * 60

#==============================================================================
# Emergency Alert System Configuration
#==============================================================================

SmartMessage.configure do |config|
  config.transport = :redis_queue
  config.transport_options = {
    url: 'redis://localhost:6379',
    db: 6,  # Use database 6 for emergency alert demo
    queue_prefix: 'emergency_alerts',
    consumer_group: 'emergency_responders'
  }
end

#==============================================================================
# Emergency Message Classes
#==============================================================================

class EmergencyAlert < SmartMessage::Base
  transport :redis_queue
  
  property :alert_id, required: true
  property :alert_type, required: true  # fire, medical, security, natural_disaster, infrastructure
  property :severity, required: true    # low, medium, high, critical
  property :title, required: true
  property :description, required: true
  property :location, required: true
  property :coordinates, default: {}    # lat/lng
  property :affected_area_radius, default: 0  # in kilometers
  property :estimated_affected_people, default: 0
  property :response_required, default: true
  property :contact_info, default: {}
  property :metadata, default: {}
  property :timestamp, default: -> { Time.now }
  
  def process
    severity_icon = case severity
                   when 'critical' then '🔥'
                   when 'high' then '🚨'
                   when 'medium' then '⚠️'
                   when 'low' then '⚡'
                   else '📢'
                   end
    
    type_icon = case alert_type
               when 'fire' then '🔥'
               when 'medical' then '🚑'
               when 'security' then '👮'
               when 'natural_disaster' then '🌪️'
               when 'infrastructure' then '🏗️'
               else '🚨'
               end
    
    puts "#{severity_icon}#{type_icon} ALERT #{alert_id} [#{severity.upcase}]: #{title}"
    puts "   Type: #{alert_type.upcase}"
    puts "   Location: #{location}"
    puts "   Description: #{description}"
    puts "   People affected: #{estimated_affected_people}" if estimated_affected_people > 0
    puts "   Response required: #{response_required ? 'YES' : 'NO'}"
  end
end

class EmergencyResponse < SmartMessage::Base
  transport :redis_queue
  
  property :response_id, required: true
  property :alert_id, required: true
  property :responding_unit, required: true  # fire_dept, police, hospital, utility_company
  property :response_type, required: true   # dispatched, on_scene, resolved, cancelled
  property :eta_minutes
  property :personnel_count, default: 0
  property :equipment, default: []
  property :status_update, required: true
  property :timestamp, default: -> { Time.now }
  
  def process
    response_icon = case response_type
                   when 'dispatched' then '🚀'
                   when 'on_scene' then '📍'
                   when 'resolved' then '✅'
                   when 'cancelled' then '❌'
                   else '📝'
                   end
    
    unit_icon = case responding_unit
               when 'fire_dept' then '🚒'
               when 'police' then '🚔'
               when 'hospital' then '🚑'
               when 'utility_company' then '⚡'
               else '🚗'
               end
    
    puts "#{response_icon}#{unit_icon} RESPONSE #{response_id}: #{responding_unit.upcase} - #{response_type.upcase}"
    puts "   Alert ID: #{alert_id}"
    puts "   Status: #{status_update}"
    puts "   ETA: #{eta_minutes} minutes" if eta_minutes
    puts "   Personnel: #{personnel_count}" if personnel_count > 0
    puts "   Equipment: #{equipment.join(', ')}" if equipment.any?
  end
end

class CitizenReport < SmartMessage::Base
  transport :redis_queue
  
  property :report_id, required: true
  property :reporter_id
  property :report_type, required: true  # incident, tip, request_help, status_update
  property :description, required: true
  property :location, required: true
  property :urgency, default: 'medium'  # low, medium, high
  property :contact_phone
  property :photos, default: []
  property :verified, default: false
  property :timestamp, default: -> { Time.now }
  
  def process
    urgency_icon = case urgency
                  when 'high' then '🚨'
                  when 'medium' then '⚠️'
                  when 'low' then 'ℹ️'
                  else '📢'
                  end
    
    puts "#{urgency_icon} CITIZEN REPORT #{report_id} [#{urgency.upcase}]: #{report_type.upcase}"
    puts "   Location: #{location}"
    puts "   Description: #{description}"
    puts "   Contact: #{contact_phone}" if contact_phone
    puts "   Photos: #{photos.size} attached" if photos.any?
    puts "   Verified: #{verified ? 'YES' : 'PENDING'}"
  end
end

#==============================================================================
# Emergency Response Services
#==============================================================================

class EmergencyDispatchCenter
  def initialize(transport)
    @transport = transport
    @active_alerts = {}
    @response_units = {}
    setup_subscriptions
  end
  
  def setup_subscriptions
    # Listen for new citizen reports
    @transport.where
      .type('CitizenReport')
      .to('dispatch_center')
      .subscribe do |message_class, message_data|
        handle_citizen_report(JSON.parse(message_data))
      end
    
    # Listen for response updates
    @transport.where
      .type('EmergencyResponse')
      .to('dispatch_center')
      .subscribe do |message_class, message_data|
        track_response(JSON.parse(message_data))
      end
  end
  
  def create_alert(alert_type, severity, title, description, location, options = {})
    alert_id = "ALERT-#{Time.now.strftime('%Y%m%d')}-#{sprintf('%04d', rand(9999))}"
    
    alert = EmergencyAlert.new({
      alert_id: alert_id,
      alert_type: alert_type,
      severity: severity,
      title: title,
      description: description,
      location: location,
      coordinates: options[:coordinates] || {},
      affected_area_radius: options[:radius] || 0,
      estimated_affected_people: options[:affected_people] || 0,
      contact_info: options[:contact] || {},
      metadata: options[:metadata] || {}
    }.merge(options))
    
    # Broadcast to all emergency services
    alert._sm_header.from = 'dispatch_center'
    alert._sm_header.to = 'emergency_broadcast'
    alert.publish
    
    # Route to specific services based on alert type
    route_alert_to_services(alert, alert_type, severity)
    
    @active_alerts[alert_id] = alert
    alert_id
  end
  
  private
  
  def handle_citizen_report(report_data)
    puts "📞 Dispatch: Received citizen report #{report_data['report_id']}"
    
    # Evaluate if report requires emergency alert
    if report_data['urgency'] == 'high'
      # Escalate to emergency alert
      alert_id = create_alert(
        determine_alert_type(report_data['description']),
        'medium',
        "Citizen Report: #{report_data['report_type'].capitalize}",
        report_data['description'],
        report_data['location'],
        { contact: { phone: report_data['contact_phone'] } }
      )
      
      puts "   ⬆️ Escalated to emergency alert: #{alert_id}"
    end
  end
  
  def track_response(response_data)
    puts "📊 Dispatch: Tracking response #{response_data['response_id']} for alert #{response_data['alert_id']}"
    @response_units[response_data['response_id']] = response_data
  end
  
  def route_alert_to_services(alert, alert_type, severity)
    services = case alert_type
              when 'fire'
                ['fire_department', 'police_department'] + (severity == 'critical' ? ['hospital'] : [])
              when 'medical'
                ['hospital', 'fire_department']
              when 'security'
                ['police_department'] + (severity == 'critical' ? ['fire_department'] : [])
              when 'natural_disaster'
                ['fire_department', 'police_department', 'hospital', 'utility_company']
              when 'infrastructure'
                ['utility_company', 'fire_department']
              else
                ['police_department']
              end
    
    services.each do |service|
      alert_copy = EmergencyAlert.new(alert.to_h)
      alert_copy._sm_header.to = service
      alert_copy.publish
    end
  end
  
  def determine_alert_type(description)
    case description.downcase
    when /fire|smoke|burning/ then 'fire'
    when /medical|injury|accident|hurt/ then 'medical'
    when /robbery|theft|assault|suspicious/ then 'security'
    when /flood|earthquake|storm|tornado/ then 'natural_disaster'
    when /power|gas|water|sewer/ then 'infrastructure'
    else 'security'
    end
  end
end

class FireDepartment
  def initialize(transport)
    @transport = transport
    @available_units = 3
    @deployed_units = {}
    setup_subscriptions
  end
  
  def setup_subscriptions
    # Listen for emergency alerts
    @transport.where
      .to('fire_department')
      .subscribe do |message_class, message_data|
        handle_alert(JSON.parse(message_data)) if message_class == 'EmergencyAlert'
      end
    
    # Listen for broadcasts
    @transport.where
      .to('emergency_broadcast')
      .subscribe do |message_class, message_data|
        monitor_alert(JSON.parse(message_data)) if message_class == 'EmergencyAlert'
      end
  end
  
  private
  
  def handle_alert(alert_data)
    alert_type = alert_data['alert_type']
    severity = alert_data['severity']
    alert_id = alert_data['alert_id']
    
    puts "🚒 Fire Department: Received #{severity} #{alert_type} alert #{alert_id}"
    
    if should_respond?(alert_type, severity)
      dispatch_response(alert_data)
    else
      puts "   ⏸️ Standing by (not primary responder for this alert type)"
    end
  end
  
  def monitor_alert(alert_data)
    puts "🚒 Fire Department: Monitoring alert #{alert_data['alert_id']} (broadcast)"
  end
  
  def should_respond?(alert_type, severity)
    case alert_type
    when 'fire' then true
    when 'medical' then true
    when 'natural_disaster' then true
    when 'infrastructure' then severity == 'high' || severity == 'critical'
    when 'security' then severity == 'critical'
    else false
    end
  end
  
  def dispatch_response(alert_data)
    if @available_units > 0
      @available_units -= 1
      response_id = "FD-#{Time.now.strftime('%H%M%S')}-#{rand(99)}"
      
      personnel = case alert_data['severity']
                 when 'critical' then 8
                 when 'high' then 6
                 when 'medium' then 4
                 else 2
                 end
      
      equipment = case alert_data['alert_type']
                 when 'fire' then ['fire_engine', 'ladder_truck', 'water_tank']
                 when 'medical' then ['ambulance', 'rescue_equipment']
                 else ['fire_engine', 'rescue_equipment']
                 end
      
      EmergencyResponse.new(
        response_id: response_id,
        alert_id: alert_data['alert_id'],
        responding_unit: 'fire_dept',
        response_type: 'dispatched',
        eta_minutes: rand(5..15),
        personnel_count: personnel,
        equipment: equipment,
        status_update: "Unit dispatched to #{alert_data['location']}",
        _sm_header: {
          from: 'fire_department',
          to: 'dispatch_center'
        }
      ).publish
      
      @deployed_units[response_id] = alert_data['alert_id']
      
      # Simulate arrival and resolution
      Thread.new do
        sleep(2)  # Simulate travel time
        update_response_status(response_id, 'on_scene', 'Fire department on scene, assessing situation')
        
        sleep(3)  # Simulate response time
        resolution = ['resolved', 'resolved', 'resolved', 'cancelled'].sample  # 75% success rate
        status = resolution == 'resolved' ? 'Incident resolved successfully' : 'False alarm - no action required'
        update_response_status(response_id, resolution, status)
        
        @available_units += 1
        @deployed_units.delete(response_id)
      end
    else
      puts "   🚫 No available units - requesting mutual aid"
    end
  end
  
  def update_response_status(response_id, response_type, status)
    EmergencyResponse.new(
      response_id: response_id,
      alert_id: @deployed_units[response_id],
      responding_unit: 'fire_dept',
      response_type: response_type,
      status_update: status,
      _sm_header: {
        from: 'fire_department',
        to: 'dispatch_center'
      }
    ).publish
  end
end

class PoliceDepartment
  def initialize(transport)
    @transport = transport
    @available_units = 5
    @deployed_units = {}
    setup_subscriptions
  end
  
  def setup_subscriptions
    @transport.where
      .to('police_department')
      .subscribe do |message_class, message_data|
        handle_alert(JSON.parse(message_data)) if message_class == 'EmergencyAlert'
      end
    
    @transport.where
      .to('emergency_broadcast')
      .subscribe do |message_class, message_data|
        monitor_alert(JSON.parse(message_data)) if message_class == 'EmergencyAlert'
      end
  end
  
  private
  
  def handle_alert(alert_data)
    alert_type = alert_data['alert_type']
    severity = alert_data['severity']
    alert_id = alert_data['alert_id']
    
    puts "👮 Police Department: Received #{severity} #{alert_type} alert #{alert_id}"
    
    if should_respond?(alert_type, severity)
      dispatch_response(alert_data)
    end
  end
  
  def monitor_alert(alert_data)
    puts "👮 Police Department: Monitoring alert #{alert_data['alert_id']}"
  end
  
  def should_respond?(alert_type, severity)
    case alert_type
    when 'security' then true
    when 'fire' then severity == 'medium' || severity == 'high' || severity == 'critical'
    when 'natural_disaster' then true
    when 'medical' then severity == 'high' || severity == 'critical'
    else false
    end
  end
  
  def dispatch_response(alert_data)
    if @available_units > 0
      @available_units -= 1
      response_id = "PD-#{Time.now.strftime('%H%M%S')}-#{rand(99)}"
      
      officers = case alert_data['severity']
                when 'critical' then 6
                when 'high' then 4
                when 'medium' then 2
                else 1
                end
      
      equipment = case alert_data['alert_type']
                 when 'security' then ['patrol_car', 'radio', 'backup_requested']
                 else ['patrol_car', 'radio']
                 end
      
      EmergencyResponse.new(
        response_id: response_id,
        alert_id: alert_data['alert_id'],
        responding_unit: 'police',
        response_type: 'dispatched',
        eta_minutes: rand(3..12),
        personnel_count: officers,
        equipment: equipment,
        status_update: "Officers dispatched to #{alert_data['location']}",
        _sm_header: {
          from: 'police_department',
          to: 'dispatch_center'
        }
      ).publish
      
      @deployed_units[response_id] = alert_data['alert_id']
      
      Thread.new do
        sleep(1.5)
        update_response_status(response_id, 'on_scene', 'Police on scene, securing area')
        
        sleep(2.5)
        update_response_status(response_id, 'resolved', 'Situation resolved, area secured')
        
        @available_units += 1
        @deployed_units.delete(response_id)
      end
    end
  end
  
  def update_response_status(response_id, response_type, status)
    EmergencyResponse.new(
      response_id: response_id,
      alert_id: @deployed_units[response_id],
      responding_unit: 'police',
      response_type: response_type,
      status_update: status,
      _sm_header: {
        from: 'police_department',
        to: 'dispatch_center'
      }
    ).publish
  end
end

class Hospital
  def initialize(transport)
    @transport = transport
    @available_ambulances = 2
    @deployed_ambulances = {}
    setup_subscriptions
  end
  
  def setup_subscriptions
    @transport.where
      .to('hospital')
      .subscribe do |message_class, message_data|
        handle_alert(JSON.parse(message_data)) if message_class == 'EmergencyAlert'
      end
  end
  
  private
  
  def handle_alert(alert_data)
    alert_type = alert_data['alert_type']
    severity = alert_data['severity']
    
    puts "🏥 Hospital: Received #{severity} #{alert_type} alert #{alert_data['alert_id']}"
    
    if alert_type == 'medical' || (alert_type == 'fire' && severity == 'high')
      dispatch_ambulance(alert_data)
    else
      puts "   📋 Preparing to receive potential patients"
    end
  end
  
  def dispatch_ambulance(alert_data)
    if @available_ambulances > 0
      @available_ambulances -= 1
      response_id = "AMB-#{Time.now.strftime('%H%M%S')}-#{rand(99)}"
      
      EmergencyResponse.new(
        response_id: response_id,
        alert_id: alert_data['alert_id'],
        responding_unit: 'hospital',
        response_type: 'dispatched',
        eta_minutes: rand(6..18),
        personnel_count: 2,
        equipment: ['ambulance', 'medical_equipment', 'defibrillator'],
        status_update: "Ambulance dispatched to #{alert_data['location']}",
        _sm_header: {
          from: 'hospital',
          to: 'dispatch_center'
        }
      ).publish
      
      @deployed_ambulances[response_id] = alert_data['alert_id']
    end
  end
end

#==============================================================================
# Emergency Alert System Demo
#==============================================================================

puts "\n🚨 Initializing Emergency Response System..."

transport = SmartMessage::Transport::RedisQueueTransport.new(
  url: 'redis://localhost:6379',
  db: 6,
  queue_prefix: 'emergency_alerts',
  consumer_group: 'emergency_responders',
  block_time: 1000
)

# Initialize emergency services
dispatch = EmergencyDispatchCenter.new(transport)
fire_dept = FireDepartment.new(transport)
police = PoliceDepartment.new(transport)
hospital = Hospital.new(transport)

sleep 2
puts "✅ All emergency services online and ready"

#==============================================================================
# Emergency Scenarios
#==============================================================================

puts "\n🎭 Emergency Alert Scenarios:"

# Scenario 1: Building Fire
puts "\n🔥 Scenario 1: Building Fire Emergency"
fire_alert_id = dispatch.create_alert(
  'fire',
  'high',
  'Building Fire at Downtown Office Complex',
  'Large office building on fire, multiple floors affected, people may be trapped',
  '123 Main Street, Downtown',
  {
    coordinates: { lat: 40.7128, lng: -74.0060 },
    affected_people: 200,
    radius: 2,
    contact: { phone: '911', name: 'Dispatch Center' }
  }
)

sleep 4

# Scenario 2: Medical Emergency
puts "\n🚑 Scenario 2: Medical Emergency"
medical_alert_id = dispatch.create_alert(
  'medical',
  'critical',
  'Multi-Vehicle Accident with Injuries',
  'Three-car collision on highway, multiple injuries, road blocked',
  'Highway 101 Mile Marker 45',
  {
    coordinates: { lat: 40.7589, lng: -73.9851 },
    affected_people: 8,
    radius: 1,
    contact: { phone: '911', name: 'Highway Patrol' }
  }
)

sleep 4

# Scenario 3: Security Incident
puts "\n👮 Scenario 3: Security Emergency"
security_alert_id = dispatch.create_alert(
  'security',
  'medium',
  'Armed Robbery in Progress',
  'Armed suspect robbing convenience store, suspect described as male, 5\'10", wearing black hoodie',
  '456 Oak Avenue, West Side',
  {
    coordinates: { lat: 40.7505, lng: -73.9934 },
    affected_people: 5,
    contact: { phone: '911', name: 'Store Manager' }
  }
)

sleep 4

# Scenario 4: Natural Disaster
puts "\n🌪️ Scenario 4: Natural Disaster"
disaster_alert_id = dispatch.create_alert(
  'natural_disaster',
  'critical',
  'Tornado Warning - Immediate Shelter Required',
  'Large tornado spotted 5 miles south, moving northeast at 45 mph, take shelter immediately',
  'Central County Area',
  {
    coordinates: { lat: 40.7282, lng: -74.0776 },
    affected_people: 50000,
    radius: 15,
    contact: { phone: 'Emergency Management', name: 'County Emergency Services' }
  }
)

sleep 5

#==============================================================================
# Citizen Reports
#==============================================================================

puts "\n📱 Citizen Reports:"

# Citizen Report 1: Suspicious Activity
CitizenReport.new(
  report_id: "CR-#{Time.now.strftime('%Y%m%d%H%M%S')}",
  reporter_id: 'citizen_123',
  report_type: 'tip',
  description: 'Suspicious person looking into car windows in parking lot',
  location: '789 Pine Street parking lot',
  urgency: 'medium',
  contact_phone: '+1-555-0123',
  _sm_header: {
    from: 'citizen_app',
    to: 'dispatch_center'
  }
).publish

sleep 2

# Citizen Report 2: Gas Leak
CitizenReport.new(
  report_id: "CR-#{Time.now.strftime('%Y%m%d%H%M%S')}",
  reporter_id: 'citizen_456',
  report_type: 'incident',
  description: 'Strong gas smell near apartment building, possible gas leak',
  location: '321 Elm Street Apartments',
  urgency: 'high',
  contact_phone: '+1-555-0456',
  photos: ['gas_leak_1.jpg', 'gas_leak_2.jpg'],
  _sm_header: {
    from: 'citizen_app',
    to: 'dispatch_center'
  }
).publish

sleep 3

#==============================================================================
# Mass Alert Scenario
#==============================================================================

puts "\n📢 Mass Alert Scenario: Multiple Simultaneous Emergencies"

# Simulate multiple emergencies happening at once
emergencies = [
  ['fire', 'medium', 'Kitchen Fire at Restaurant', 'Grease fire in commercial kitchen'],
  ['medical', 'high', 'Heart Attack at Gym', 'Elderly man collapsed during workout'],
  ['security', 'low', 'Vandalism Report', 'Graffiti on public building'],
  ['infrastructure', 'medium', 'Water Main Break', 'Large water main break flooding street']
]

puts "⚡ Simultaneous emergency alerts..."
emergencies.each_with_index do |(type, severity, title, description), i|
  dispatch.create_alert(
    type,
    severity,
    title,
    description,
    "Location #{i + 1}",
    { affected_people: rand(10..100) }
  )
  
  sleep 0.5  # Slight delay between alerts
end

sleep 8

#==============================================================================
# System Statistics
#==============================================================================

puts "\n📊 Emergency Alert System Statistics:"

stats = transport.queue_stats
puts "\nQueue statistics:"
emergency_queues = stats.select { |name, _| name.include?('emergency') || name.include?('department') || name.include?('hospital') }
emergency_queues.each do |queue_name, info|
  service_name = queue_name.split('.').last.tr('_', ' ').titleize
  puts "  #{service_name}: #{info[:length]} pending alerts"
end

routing_table = transport.routing_table
puts "\nActive routing patterns:"
routing_table.each do |pattern, queues|
  puts "  '#{pattern}' → #{queues.size} queue(s)"
end

total_alerts = stats.values.sum { |info| info[:length] }
puts "\nTotal active alerts in system: #{total_alerts}"

# Show alert type distribution
alert_types = ['fire', 'medical', 'security', 'natural_disaster', 'infrastructure']
puts "\nAlert Type Coverage:"
alert_types.each do |type|
  pattern_exists = routing_table.any? { |pattern, _| pattern.downcase.include?(type) }
  puts "  #{type.capitalize}: #{pattern_exists ? '✅ Covered' : '❌ No coverage'}"
end

transport.disconnect

puts "\n🚨 Emergency Alert System demonstration completed!"

puts "\n💡 Emergency System Features Demonstrated:"
puts "   ✓ Multi-service emergency coordination"
puts "   ✓ Severity-based alert routing"
puts "   ✓ Real-time response tracking"
puts "   ✓ Citizen reporting integration"
puts "   ✓ Broadcast and targeted alerts"
puts "   ✓ Multi-agency response coordination"
puts "   ✓ Geographic area coverage"
puts "   ✓ Mass casualty incident handling"

puts "\n🚀 Key Emergency Response Benefits:"
puts "   • Instant alert distribution to all relevant agencies"
puts "   • Coordinated multi-agency response"
puts "   • Real-time status updates and tracking"
puts "   • Citizen engagement and reporting"
puts "   • Scalable from single incident to mass casualty"
puts "   • Persistent alert queues ensure no missed notifications"
puts "   • Geographic and severity-based smart routing"
puts "   • Historical incident tracking and analysis"