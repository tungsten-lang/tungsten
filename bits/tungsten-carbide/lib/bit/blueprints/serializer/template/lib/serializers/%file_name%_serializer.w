# %class_name%Serializer — JSON representation of %class_name%
use Tungsten:Carbide

+ %class_name%Serializer < Carbide:Serializer
  attributes :id

  # Add model attributes to serialize:
  # attributes :name, :email, :created_at

  # Relationships:
  # has_many :comments, serializer: CommentSerializer
  # belongs_to :author, serializer: UserSerializer

  # Custom computed attribute
  # -> display_name
  #   "#{object.first_name} #{object.last_name}"
