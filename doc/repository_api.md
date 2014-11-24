# Suggested API for repositories

```ruby
# Returns whether a component matching the parameters is available in the repo.
#
# @param [String] name
# @param [nil|String|Gem::Requirement|Gem::Version] version
# @return [true|false]
#
# If version is nil, any version of the component is considered available.
# If version is a Gem::Version, only that specific version is considered available
# If version is a String or a Gem::Requirement, any version that satisfies the requirement
# is considered available. 
def available?(name, version = nil)
end
```

```ruby
# Returns a list of the versions of the specified component availalable from the repo.
#
# @param [String] name
# @return [Array]
#
# The return value will be an array of Gem::Version objects.
#
def available_versions(name)
end
```

```ruby
# Returns a list of the components availalable from the repo. Only the names are returned.
#
# @return [Array]
#
# To extract both component names and their available versions, the following code can be used
# repo.list_components.reduce({}) do |memo, name|
#   memo[name] = repo.available_versions(name)
# end
#
def list_components()
end
```

```ruby
# Returns the component matching the parameters from the repo or nil if
# the component is not available.
#
# @param [String] name
# @param [Gem::Version] version
# @return [Diversity::Component|nil]
# @alias get_component
#
def [](name, version)
end
```

```ruby
# Returns all components matching the parameters from the repo or an empty list if
# no matching components are available.
#
# @param [String] name
# @param [nil|String|Gem::Requirement|Gem::Version] version
# @return [Array]
#
# If version is nil, any version of the component is included.
# If version is a Gem::Version, only that specific version is included.
# If version is a String or a Gem::Requirement, any version that satisfies the requirement
# is included. 
def get_matching_components?(name, version = nil)
end
```
