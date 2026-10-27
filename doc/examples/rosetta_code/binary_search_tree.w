# Binary search tree

+ BSTNode
  rw :value, :left, :right

  -> new(@value)
    @left = nil
    @right = nil

-> bst_insert(root, val)
  if root == nil
    return BSTNode.new(val)
  if val < root.value
    root.left = bst_insert(root.left, val)
  elsif val > root.value
    root.right = bst_insert(root.right, val)
  root

-> bst_inorder(node, out)
  if node == nil
    return
  bst_inorder(node.left, out)
  out.push(node.value)
  bst_inorder(node.right, out)

-> bst_contains?(node, val)
  if node == nil
    return false
  if val == node.value
    return true
  if val < node.value
    bst_contains?(node.left, val)
  else
    bst_contains?(node.right, val)

root = nil
vals = [5, 3, 7, 2, 4, 6, 8]
vals.each -> (v)
  root = bst_insert(root, v)

sorted = []
bst_inorder(root, sorted)
<< sorted
<< bst_contains?(root, 4)
<< bst_contains?(root, 9)

## expect stdout
## [2, 3, 4, 5, 6, 7, 8]
## true
## false
