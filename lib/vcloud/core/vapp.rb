module Vcloud
  module Core
    class Vapp
      extend ComputeMetadata

      attr_reader :id

      def initialize(id)
        unless id =~ /^#{self.class.id_prefix}-[-0-9a-f]+$/
          raise "#{self.class.id_prefix} id : #{id} is not in correct format"
        end
        @id = id
      end

      def self.get_by_name(name)
        q = Vcloud::Core::QueryRunner.new
        query_results = q.run('vApp', :filter => "name==#{name}")
        raise "Error finding vApp by name #{name}" unless query_results
        case query_results.size
        when 0
          raise "vApp #{name} not found"
        when 1
          return self.new(query_results.first[:href].split('/').last)
        else
          raise "found multiple vApp entities with name #{name}!"
        end
      end

      def vcloud_attributes
        Vcloud::Core::Fog::ServiceInterface.new.get_vapp(id)
      end

      module STATUS
        RUNNING = 4
        POWERED_OFF = 8
      end

      def name
        vcloud_attributes[:name]
      end

      def href
        vcloud_attributes[:href]
      end

      def vm_href
        vms.first[:href]
      end

      def vdc_id
        link = vcloud_attributes[:Link].detect do |l|
          l[:rel] == Fog::RELATION::PARENT && l[:type] == Fog::ContentTypes::VDC
        end
        link ? link[:href].split('/').last : raise('a vapp without parent vdc found')
      end

      def vms
        vcloud_attributes[:Children][:Vm]
      end

      def networks
        vcloud_attributes[:'ovf:NetworkSection'][:'ovf:Network']
      end

      def self.get_by_name_and_vdc_name(name, vdc_name)
        fog_interface = Vcloud::Core::Fog::ServiceInterface.new
        attrs = fog_interface.get_vapp_by_name_and_vdc_name(name, vdc_name)
        self.new(attrs[:href].split('/').last) if attrs && attrs.key?(:href)
      end

      def self.instantiate(name, template_id, vdc_name, org_networks, vapp_networks)
        Vcloud::Core.logger.info("Instantiating new vApp #{name} in vDC '#{vdc_name}'")
        fog_interface = Vcloud::Core::Fog::ServiceInterface.new

        networks = get_org_networks(org_networks, vdc_name)
        params = build_network_config(networks)
        params[:NetworkConfigSection][:NetworkConfig] +=
          build_vapp_network_config(vapp_networks, vdc_name)

        attrs = fog_interface.post_instantiate_vapp_template(
            fog_interface.vdc(vdc_name),
            template_id,
            name,
            InstantiationParams: params
        )
        self.new(attrs[:href].split('/').last) if attrs and attrs.key?(:href)
      end

      def self.get_vapp_networks(vapp_networks, vdc_name)
        vapp_networks.collect do |network|
          output = {
            :name => network[:name],
            :fence_mode => fence_mode(network[:fence_mode])
          }
          if network[:parent_network]
            parent_network_href = get_org_networks([network[:parent_network]], vdc_name).first.
              fetch(:href) { raise "Cannot find link for parent network #{network[:parent_network]}" }
            output.merge!({ href: parent_network_href })
          end
          output
        end
      end

      def recompose(vapp_name, vdc_name, vm_config, org_networks, vapp_networks)
        Vcloud::Core.logger.info("Recomposing vApp #{vapp_name} to add VM #{vm_config[:name] || vapp_name}")
        fog_interface = Vcloud::Core::Fog::ServiceInterface.new

        vm_config[:href] ||= vm_href
        vm_config[:networks] = vm_network_config(vm_config[:network_connections])

        fog_config = {}
        fog_config[:vapp_name] = vapp_name
        fog_config[:source_vms] = [vm_config]
        org_network_params = self.class.get_org_networks(org_networks, vdc_name)
        vapp_network_params = self.class.get_vapp_networks(vapp_networks, vdc_name)
        fog_config[:InstantiationParams] =
          self.class.build_network_config(org_network_params + vapp_network_params)

        fog_interface.post_recompose_vapp(id, fog_config)

        self
      end

      def vm_network_config(network_configs)
        network_configs.collect do |config|
          new_config = {}
          new_config[:networkName] = config[:name]
          new_config[:IpAddress] = config[:ip_address]
          new_config[:IpAddressAllocationMode] = (config[:allocation_mode] || 'manual').upcase
          new_config[:IsConnected] = 'true'
          new_config
        end
      end

      def power_on
        raise "Cannot power on a missing vApp." unless id
        return true if running?
        Vcloud::Core::Fog::ServiceInterface.new.power_on_vapp(id)
        running?
      end

      private
      def running?
        raise "Cannot call running? on a missing vApp." unless id
        vapp = Vcloud::Core::Fog::ServiceInterface.new.get_vapp(id)
        vapp[:status].to_i == STATUS::RUNNING ? true : false
      end

      def self.build_network_config(networks)
        return {} unless networks
        instantiation = { NetworkConfigSection: { NetworkConfig: [] } }
        networks.compact.each do |network|
          network_config = {
            networkName: network[:name],
            Configuration: {
              FenceMode: fence_mode(network[:fence_mode])
            }
          }

          unless network_config[:Configuration][:FenceMode] == 'isolated'
            network_config[:Configuration][:ParentNetwork] = { href: network[:href] }
          end

          instantiation[:NetworkConfigSection][:NetworkConfig] << network_config
        end
        instantiation
      end

      def self.fence_mode(mode)
        return 'natRouted' unless mode
        case mode
        when /^nat/
          'natRouted'
        when /^iso/
          'isolated'
        end
      end

      def self.build_vapp_network_config(networks, vdc_name=nil)
        return [] unless networks
        config = []
        networks.compact.each do |network|
          network_config = {
            networkName: network[:name],
            Configuration: {
              IpScopes: {
                IpScope: {
                  IsInherited: false,
                  Gateway: network[:gateway],
                  Netmask: network[:netmask],
                  IpRanges: {
                    IpRange: {
                      StartAddress: network[:start_address],
                      EndAddress: network[:end_address],
                    },
                  },
                },
              },
              FenceMode: fence_mode(network[:fence_mode]),
            }
          }
          unless network_config[:Configuration][:FenceMode] == 'isolated'
            parent_network_href = get_org_networks([network.fetch(:parent_network)], vdc_name).first.
              fetch(:href) { raise "Cannot find link for parent network #{network.fetch(:parent_network)}" }
            network_config[:Configuration][:ParentNetwork] = { href: parent_network_href }
          end
          config << network_config
        end
        config
      end

      def self.id_prefix
        'vapp'
      end

      def self.get_org_networks(org_networks, vdc_name)
        fsi = Vcloud::Core::Fog::ServiceInterface.new
        fsi.find_networks(org_networks, vdc_name)
      end
    end
  end
end
