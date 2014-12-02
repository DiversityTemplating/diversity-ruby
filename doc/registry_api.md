# Suggested API for registries

```ruby
# Returns the component matching the parameters from the registry or nil if
# the component is not available. If multiple versions of the component is matching
# the component with the highest version is returned.
#
# @param [String] component
# @param [nil|String|Gem::Requirement|Gem::Version] version
# @return [Diversity::Component|nil]
# @alias get
#
# If version is nil, the highest version of the component will be returned.
# If version is a Gem::Version, that specific version will be returned.
# If version is a String or a Gem::Requirement, the highest version that satisfies the requirement
# is returned.
def [](component, version = nil)
end
```

```ruby
# Returns whether a component matching the parameters is available in the registry.
#
# @param [String] component
# @param [nil|String|Gem::Requirement|Gem::Version] version
# @return [true|false]
#
# If version is nil, any version of the component is considered available.
# If version is a Gem::Version, only that specific version is considered available
# If version is a String or a Gem::Requirement, any version that satisfies the requirement
# is considered available.
def available?(component, version = nil)
end
```

```ruby
# Returns an array of the components availalable from the registry. Only the component names
# are returned.
#
# @return [Array]
#
# To extract both component names and their available versions, the following code can be used
# registry.components.reduce({}) do |memo, component|
#   memo[component] = registry.versions(component)
# end
#
def components()
end
```

```ruby
# Returns an array of the versions of the specified component matching the parameters.
# The return value will be an array of Gem::Version objects. If no matching versions is available
# from the registry, an empty array is returned.
#
# @param [String] component
# @param [nil|String|Gem::Requirement|Gem::Version] version
# @return [Array]
#
# If version is nil, all versions of the component is returned.
# If version is a Gem::Version, only that specific version returned
# If version is a String or a Gem::Requirement, any version that satisfies the requirement
# is returned.
#
def versions(component, version = nil)
end
```
