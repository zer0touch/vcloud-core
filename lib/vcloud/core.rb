require 'open3'
require 'vcloud/core/timeout'
require 'vcloud/core/fog'
require 'vcloud/core/api_interface'

require 'vcloud/core/version'

require 'vcloud/core/config_loader'
require 'vcloud/core/config_validator'
require 'vcloud/core/entity'
require 'vcloud/core/metadata_helper'
require 'vcloud/core/compute_metadata'
require 'vcloud/core/vdc'
require 'vcloud/core/edge_gateway'
require 'vcloud/core/edge_gateway_interface'
require 'vcloud/core/login_cli'
require 'vcloud/core/logout_cli'
require 'vcloud/core/vm'
require 'vcloud/core/vapp'
require 'vcloud/core/vapp_template'
require 'vcloud/core/independent_disk'
require 'vcloud/core/org_vdc_network'
require 'vcloud/core/query'
require 'vcloud/core/query_cli'
require 'vcloud/core/query_runner'

module Vcloud
  module Core

    def self.logger
      @logger ||=Logger.new(STDOUT)
    end

  end
end
