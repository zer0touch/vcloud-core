module Vcloud
  module Core
    case ENV['VCLOUD_TIMEOUT']
    when nil
      TIMEOUT = 600
    else
      TIMEOUT = ENV['VCLOUD_TIMEOUT'].to_i
    end
  end
end
