class Module
  def simple_name
    name.gsub(/^.*::/, '')
        .gsub(/([a-z\d])([A-Z])/, '\1_\2')
  end
end
