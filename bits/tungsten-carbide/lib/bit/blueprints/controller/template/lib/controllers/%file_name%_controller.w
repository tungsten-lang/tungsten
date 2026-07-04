# %class_name%Controller — handles %name% requests
use Tungsten:Carbide

+ %class_name%Controller < ApplicationController
  # before_action :find_%file_name%, only: [:show, :edit, :update, :destroy]

  -> index
    assign(:%file_name%s, %class_name%.all)

  -> show
    assign(:%file_name%, find_%file_name%)

  -> new
    assign(:%file_name%, %class_name%.new)

  -> create
    %file_name% = %class_name%.new(%file_name%_params)
    if %file_name%.save
      redirect_to("/%name%/#{%file_name%.id}")
    else
      assign(:%file_name%, %file_name%)
      render(:new)

  -> edit
    assign(:%file_name%, find_%file_name%)

  -> update
    %file_name% = find_%file_name%
    if %file_name%.update(%file_name%_params)
      redirect_to("/%name%/#{%file_name%.id}")
    else
      assign(:%file_name%, %file_name%)
      render(:edit)

  -> destroy
    find_%file_name%.destroy
    redirect_to("/%name%")

  # --- Private ---

  -> find_%file_name%
    %class_name%.find(params[:id])

  -> %file_name%_params
    permit(:%file_name%).require(:%file_name%)
