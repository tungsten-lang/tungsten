# %class_name%Lookup — encapsulated query object
# Keeps complex queries out of models and controllers.
#
# Usage:
#   results = %class_name%Lookup.new(scope: User.all, params: {active: true}).call
use Tungsten:Carbide

+ %class_name%Lookup
  ro :scope
  ro :params

  -> new(scope:, params: {})
    @scope  = scope
    @params = params

  # Execute the lookup and return results
  -> call
    result = @scope
    result = apply_filters(result)
    result = apply_ordering(result)
    result = apply_pagination(result)
    result

  # Override in subclasses to add filter logic
  -> apply_filters(scope)
    # Example:
    #   scope = scope.where(active: true) if @params[:active]
    #   scope = scope.where("created_at > ?", @params[:since]) if @params[:since]
    scope

  -> apply_ordering(scope)
    if @params[:order_by]
      direction = @params[:order_dir] || :asc
      scope.order(@params[:order_by] => direction)
    else
      scope

  -> apply_pagination(scope)
    if @params[:page]
      per_page = @params[:per_page] || 25
      offset = (@params[:page] - 1) * per_page
      scope.limit(per_page).offset(offset)
    else
      scope

  # Convenience: call directly on the class
  -> .call(**kwargs)
    self.new(**kwargs).call
