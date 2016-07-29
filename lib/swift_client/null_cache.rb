
class SwiftClient::NullCache
  def get(key)
    nil
  end

  def set(key, value)
    true
  end
end

