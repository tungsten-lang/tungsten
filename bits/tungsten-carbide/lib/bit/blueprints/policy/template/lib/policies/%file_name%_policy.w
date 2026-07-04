in Policies

+ %class_name%Policy[Policy]
  # permit :name, :description, on: :update

  -> authorize?(action)
    case action
      :index  => true
      :show   => true
      :create => self.account.present?
      :update => self.owner?
      :destroy => self.owner?
      => false

  -> owner?
    self.record.account_id == self.account.id

  -> scope
    self.record.class.all
