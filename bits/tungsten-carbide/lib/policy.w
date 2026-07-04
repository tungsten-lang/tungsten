# Carbide::Policy — authorization
# Determines what a user is allowed to do with a given record.
# Defines permitted attributes and scoping for collections.

in Tungsten:Carbide

+ Policy
  ro :account
  ro :record

  -> new(@account, @record)

  # Override in subclasses — return true/false
  -> authorize?(action)
    false

  # Convenience methods for common actions
  -> index?   = self.authorize?(:index)
  -> show?    = self.authorize?(:show)
  -> create?  = self.authorize?(:create)
  -> update?  = self.authorize?(:update)
  -> destroy? = self.authorize?(:destroy)

  # --- Permitted attributes DSL ---

  @@permitted_attributes = {}

  -> .permit(*attributes, on: :all)
    @@permitted_attributes[on] = attributes

  -> permitted_attributes(action = :all)
    @@permitted_attributes[action] || @@permitted_attributes[:all] || []

  # --- Scoping ---
  # Override to restrict which records the user can see

  -> scope
    self.record.class.all

  # --- Class-level authorization helper ---

  -> .authorize(account, record, action)
    policy = self.new(account, record)
    unless policy.authorize?(action)
      <! NotAuthorizedError.new(
        "#{account} is not authorized to #{action} #{record.class.name}"
      )
    policy

  # --- Controller integration ---

  -> .for(record)
    # Infer policy class from record: Bit → BitPolicy
    policy_name = "#{record.class.name}Policy"
    Object.const_get(policy_name)


+ NotAuthorizedError < StandardError
