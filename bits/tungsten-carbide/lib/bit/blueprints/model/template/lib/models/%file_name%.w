# %class_name% model
use Tungsten:Carbide

+ %class_name% < Carbide:Model
  # Table name (inferred from class name if omitted)
  # table_name :%file_name%s

  # --- Attributes ---
  # attribute :name,  type: :string
  # attribute :email, type: :string

  # --- Validations ---
  # validates :name, presence: true
  # validates :email, presence: true, format: {with: /@/}

  # --- Associations ---
  # has_many :comments
  # belongs_to :author, class_name: "User"

  # --- Callbacks ---
  # before_save :normalize_name

  # --- Scopes ---
  # scope :recent, -> { order(created_at: :desc).limit(10) }
  # scope :active, -> { where(active: true) }

  # --- Instance methods ---

  -> to_s
    "#<%class_name% id=#{id}>"
