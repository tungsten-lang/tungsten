# %class_name%View — assembles data for %name% templates
# View classes sit between controllers and templates. They hold
# the logic for what data a template needs, keeping both
# controllers and templates clean.
use Tungsten:Carbide

+ %class_name%View
  ro :scope
  ro :locals

  -> new(scope: nil, locals: {})
    @scope  = scope
    @locals = locals

  # Render the view with its associated template
  -> render(template: "%file_name%/index", layout: "application")
    Carbide:View.new(template, layout: layout, locals: view_locals).render

  # Assemble the data the template needs
  -> view_locals
    @locals.merge({
      # Add computed/derived data here:
      # title: page_title,
      # items: filtered_items
    })

  # Example computed properties:
  #
  # -> page_title
  #   "%class_name%"
  #
  # -> filtered_items
  #   @scope.order(created_at: :desc)

  # Render a partial within this view's context
  -> render_partial(name, extra_locals: {})
    Carbide:View.new(name, layout: nil, locals: view_locals.merge(extra_locals)).render
