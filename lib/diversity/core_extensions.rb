# https://www.ruby-forum.com/topic/142809
class Hash
   def keep_merge(hash)
      target = dup
      hash.keys.each do |key|
         if hash[key].is_a? Hash and self[key].is_a? Hash
            target[key] = target[key].keep_merge(hash[key])
            next
         end
         #target[key] = hash[key]
         target.update(hash) { |key, *values| values.flatten.uniq }
      end
      target
   end
end
