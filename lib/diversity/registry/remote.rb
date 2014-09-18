module Diversity
  module Registry
    # Class representing a remote registry
    class Remote < Base
      # Returns a list of installed components
      #
      # @return [Array] An array of Component objects
      def installed_components
        []
      end
    end
  end
end
