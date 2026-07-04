# # Examples
#
# ```
# # Hashable protocol used by `Hash` module.
# protocol Hash
#   use Behavior
#
#   - delete/1
#   - fetch/1
#   - put/2
#   - reduce/2
#   - size/0
#
#   hook :use
#     quote
#       @behavior Hash
#
#       -> drop/1
#       -> equal/1
#       -> fetch!/1
#       -> get/1
#       -> get/2
#       -> get_lazy/2
#       -> get_and_update/2
#       -> has_key?/1
#       -> keys/0
#       -> merge/1
#       -> merge/2
#       -> pop/1
#       -> pop/2
#       -> pop_lazy/2
#       -> put_new/2
#       -> put_new_lazy/2
#       -> split/1
#       -> take/1
#       -> to_list/0
#       -> update/3
#       -> update!/2
#       -> values/0
#
# module MyHash
#   use Hash
#
#   -> delete/1
#   -> fetch/1
#   -> put/2
#   -> reduce/2
#   -> size/0
#
# describe MyHash
#   test Hash
#
# ```
#
+ Protocol
