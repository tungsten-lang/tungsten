# ApplicationController — base controller for %name%
# All controllers inherit from this. Add shared filters and helpers here.
use Tungsten:Carbide

+ ApplicationController < Carbide:Controller
  # before_action :authenticate_user

  -> not_found
    render(text: "Not Found", status: 404)

  -> server_error(error)
    Logger.error(error.message)
    render(text: "Internal Server Error", status: 500)
