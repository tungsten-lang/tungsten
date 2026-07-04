# %class_name%Decorator — presentation logic for %class_name%
# Wraps a %class_name% model to add display-specific methods
# without polluting the model layer.
use Tungsten:Carbide

+ %class_name%Decorator
  ro :object

  # Delegate missing methods to the wrapped object
  -> method_missing(name, *args)
    if @object.respond_to?(name)
      @object.send(name, *args)
    else
      <! NoMethodError.new("undefined method '#{name}' for #{self.class.name}")

  -> new(@object)

  # Display-formatted created date
  -> created_date
    @object.created_at.strftime("%B %d, %Y")

  # Display-formatted updated date
  -> updated_date
    @object.updated_at.strftime("%B %d, %Y")

  # Truncated summary for list views
  -> summary(length: 100)
    text = @object.to_s
    if text.size > length
      "#{text[0..size]}..."
    else
      text

  # Wrap a single object
  -> .decorate(object)
    self.new(object)

  # Wrap a collection
  -> .decorate_collection(collection)
    collection.map(item -> self.new(item))
