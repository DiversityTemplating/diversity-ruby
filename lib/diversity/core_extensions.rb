# coding: utf-8
# https://www.ruby-forum.com/topic/142809
class Hash
  # Recursive merge of Hash
  #
  # @param [Hash] hash
  def keep_merge(hash)
    target = dup
    hash.keys.each do |key|
      if hash[key].is_a?(Hash) && self[key].is_a?(Hash)
        target[key] = target[key].keep_merge(hash[key])
        next
      end
      target[key] = hash[key]
    end
    target
  end
end
