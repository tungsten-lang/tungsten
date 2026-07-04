# Carbide::Serializer — JSON serialization for API responses
# Define which attributes and relationships to include in JSON output.

in Tungsten:Carbide

+ Serializer
  ro :object
  ro :scope

  @@attributes_list   = []
  @@relationships     = []
  @@custom_methods    = []

  # --- Class-level DSL ---

  -> .attributes(*names)
    @@attributes_list += names

  -> .has_many(name, serializer: nil)
    @@relationships.push({name: name, type: :has_many, serializer: serializer})

  -> .has_one(name, serializer: nil)
    @@relationships.push({name: name, type: :has_one, serializer: serializer})

  -> .belongs_to(name, serializer: nil)
    @@relationships.push({name: name, type: :belongs_to, serializer: serializer})

  # --- Instance ---

  -> new(@object, scope: nil)
    @scope = scope

  -> as_json
    data = {}

    # Serialize declared attributes
    @@attributes_list.each -> (attr)
      data[attr] = if self.respond_to?(attr)
        self.send(attr)
      else
        @object.send(attr)

    # Serialize relationships
    @@relationships.each -> (rel)
      data[rel.name] = serialize_relationship(rel)

    data

  -> to_json
    as_json |> JSON.encode

  # Serialize a collection of objects
  -> .serialize(collection, scope: nil)
    collection.map(obj -> self.new(obj, scope: scope).as_json)

  -> .serialize_json(collection, scope: nil)
    serialize(collection, scope: scope) |> JSON.encode

  -> serialize_relationship(rel)
    related = @object.send(rel.name)
    serializer_class = rel.serializer || infer_serializer(rel.name, rel.type)

    case rel.type
      :has_many =>
        related.map(item -> serializer_class.new(item, scope: @scope).as_json)
      :has_one, :belongs_to =>
        if related
          serializer_class.new(related, scope: @scope).as_json
        else
          nil

  -> infer_serializer(name, type)
    class_name = case type
      :has_many => name.to_s.singularize.classify
      =>         name.to_s.classify
    Object.const_get("#{class_name}Serializer")
