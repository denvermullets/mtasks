# base class for service objects
class Service
  def self.call(...)
    new(...).call
  end
end
