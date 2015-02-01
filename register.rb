#!/usr/local/bin/ruby

require 'json'
require 'docker'

ETCD_ENDPOINT = ENV['ETCD_ENDPOINT']
if ETCD_ENDPOINT.nil? || ETCD_ENDPOINT.empty?
  puts "ETCD_ENDPOINT is not set... aborting"
  exit -1
end

HOST_IP = ENV['HOST_IP']
if HOST_IP.nil? || HOST_IP.empty?
  puts "HOST_IP is not set... aborting"
  exit -1
end

# <host ip>/<image_name>/<container id>/<private port>/<ip>:<public port>
# e.g. "10.100.100.100/dockerfile::elasticsearch:latest/f024714f6b3e6d38d9675fb7/9200/10.100.100.100:49357"
KEY_PREFIX = "registered".freeze
HOST_KEY_FORMAT = "%s".freeze
IMAGE_KEY_FORMAT = "%s".freeze
CONTAINER_KEY_FORMAT = "%s".freeze
PORT_KEY_FORMAT = "%d/%s:%d".freeze

def fix_image_name(image_name)
  image_name.gsub('/', "::")
end

def image_name_for(container)
  (container.info['Config'] && container.info['Config']['Image']) || container.info['Image']
end

def key_for_host
  "#{KEY_PREFIX}/#{HOST_KEY_FORMAT}" % HOST_IP
end

def key_for_image(image_name)
  "#{key_for_host}/#{IMAGE_KEY_FORMAT}" % fix_image_name(image_name)
end

def key_for_container(image_name, container_id)
  "#{key_for_image(image_name)}/#{CONTAINER_KEY_FORMAT}" % container_id
end

def ip_of_interest?(ip)
  ip != "0.0.0.0" && ip != "127.0.0.1" && ip != "localhost"
end

def port_of_interest?(port_info)
  port_info && port_info.key?(:ip) && ip_of_interest?(port_info[:ip])
end

def interesting_ports_for(image_name, container)
  ports = container.info['NetworkSettings']['Ports']
  return [] if ports.nil? || ports.empty?

  ports.flat_map do |private_port, public_ports|
    public_ports.map do |public_port|
      match_data = /(?<private_port_number>[^\/]*)\/(?<port_type>.*)/.match(private_port)

      if match_data
        {
          container: container.id,
          image: fix_image_name(image_name),
          ip: public_port['HostIp'],
          public_port: public_port['HostPort'],
          private_port: match_data[:private_port_number],
          port_type: match_data[:port_type]
        }
      end
    end.compact if public_ports
  end.compact.select { |port_info| port_of_interest?(port_info) }
end

def register_container(image_name, container_id)
  container = Docker::Container.get(container_id)
  ports_info = interesting_ports_for(image_name, container)
  unless ports_info.empty?
    puts "Registering ports: #{ports_info.inspect}"
    `curl -sL "#{ETCD_ENDPOINT}/v2/keys/#{key_for_container(image_name, container_id)}" -XPUT -d value="#{ports_info.to_json.gsub('"', '\"')}"`
  end
end

def unregister_container(image_name, container_id)
  puts "Unregistering container #{container_id} for image #{image_name}"
  `curl -sL "#{ETCD_ENDPOINT}/v2/keys/#{key_for_container(image_name, container_id)}?recursive=true" -XDELETE`
  # Delete the image directory if empty
  `curl -sL "#{ETCD_ENDPOINT}/v2/keys/#{key_for_image(image_name)}?dir=true" -XDELETE`
  # Delete the host directory if empty
  `curl -sL "#{ETCD_ENDPOINT}/v2/keys/#{key_for_host}?dir=true" -XDELETE`
end

def next_docker_event
  loop do
    begin
      Docker::Event.stream { |e| return e }
    rescue Docker::Error::TimeoutError
      # no-op
    rescue Docker::Error::ServerError
      puts "Waiting for docker to restart"
      sleep 10
    end
  end
end

def process_docker_events
  loop do
    next_docker_event.tap do |event|
      case event && event.status
      when 'start'
        register_container(event.from, event.id)
      when 'die'
        unregister_container(event.from, event.id)
      end
    end
  end
end

def unregister_host_containers
  puts "Unregistering all containers on this host"
  `curl -sL "#{ETCD_ENDPOINT}/v2/keys/#{key_for_host}?recursive=true" -XDELETE`
end

def register_running_containers
  Docker::Container.all.each do |container|
    register_container(container.info['Image'], container.id)
  end
end

puts "Starting container registration service using ETCD_ENDPOINT=#{ETCD_ENDPOINT} for HOST_IP=#{HOST_IP}"
unregister_host_containers
register_running_containers
process_docker_events
