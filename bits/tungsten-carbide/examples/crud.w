# Carbide CRUD demo — the full loop: Model + validations + JSON API
# served through forge's HTTP/1.1 Server. Compiled-only (Socket is a
# compiled-runtime builtin).
#
# Compile and run (from the repo root):
#   bin/tungsten -o /tmp/carbide_crud bits/tungsten-carbide/examples/crud.w
#   /tmp/carbide_crud 18200
#
# Then:
#   curl -i -X POST -H 'Content-Type: application/json' \
#        -d '{"title": "buy milk"}' http://127.0.0.1:18200/tasks   # -> 201
#   curl -i -X POST -H 'Content-Type: application/json' \
#        -d '{"title": ""}' http://127.0.0.1:18200/tasks           # -> 422 + errors
#   curl -i http://127.0.0.1:18200/tasks                           # -> 200 list
#   curl -i http://127.0.0.1:18200/tasks/1                         # -> 200 record
#   curl -i http://127.0.0.1:18200/tasks/99                        # -> 404
#   curl -i -X PUT -H 'Content-Type: application/json' \
#        -d '{"title": "buy oat milk"}' http://127.0.0.1:18200/tasks/1
#   curl -i -X DELETE http://127.0.0.1:18200/tasks/1               # -> 200 deleted
#
# The port is the first CLI argument (default 18200). `use carbide`
# pulls the whole framework (routing + controllers + Model + Serializer);
# the manifest's CLI entry point only reacts to recognized carbide
# commands, so this demo's own argv (a port number) passes through.

use carbide

+ Task < Model
  -> table
    "tasks"

  -> title_length_error
    msg = nil
    t = get(:title)
    if t != nil && t != "" && t.to_s.size < 3
      msg = "title is too short (minimum 3 characters)"
    msg

  -> validations
    checks = []
    checks.push(Model.presence(:title))
    length_check = -> (m) m.title_length_error
    checks.push(Model.custom(:title, length_check))
    checks

+ TasksController < Controller
  # JSON.parse (compiled core) returns string keys; Model attributes are
  # symbol-keyed, so the boundary symbolizes. No/invalid JSON body -> {}.
  -> body_attrs
    attrs = {}
    payload = @request.json_body
    if payload != nil
      payload.each -> (k, v)
        attrs[k.to_sym] = v
    attrs

  # GET /tasks
  -> index
    rows = []
    Model.all(Task).each -> (t)
      rows.push(t.to_h)
    render_json(rows)

  # POST /tasks
  -> create
    task = Model.create(Task, body_attrs)
    if task.persisted?
      render_json(task.to_h, {status: 201})
    else
      render_errors(task.errors)

  # GET /tasks/:id
  -> show
    task = Model.find(Task, param(:id).to_i)
    if task == nil
      render_json({error: "task not found"}, {status: 404})
    else
      render_json(task.to_h)

  # PUT /tasks/:id
  -> update
    task = Model.find(Task, param(:id).to_i)
    if task == nil
      render_json({error: "task not found"}, {status: 404})
    elsif task.update(body_attrs)
      render_json(task.to_h)
    else
      render_errors(task.errors)

  # DELETE /tasks/:id
  -> destroy
    task = Model.find(Task, param(:id).to_i)
    if task == nil
      render_json({error: "task not found"}, {status: 404})
    else
      task.destroy
      render_json({deleted: true})

port = 18200
args = argv()
if args.size > 0
  port = args[0].to_i

routes = Carbide.instance.routes
routes.get("/tasks", TasksController, -> (c) c.index)
routes.post("/tasks", TasksController, -> (c) c.create)
routes.get("/tasks/:id", TasksController, -> (c) c.show)
routes.put("/tasks/:id", TasksController, -> (c) c.update)
routes.delete("/tasks/:id", TasksController, -> (c) c.destroy)

Carbide.run("127.0.0.1", port)
