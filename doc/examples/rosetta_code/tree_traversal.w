# Tree traversal

+ TreeNode
  -> new(@val, @left, @right) ro

-> preorder(node, out)
  if node == nil
    return
  out.push(node.val)
  preorder(node.left, out)
  preorder(node.right, out)

-> inorder(node, out)
  if node == nil
    return
  inorder(node.left, out)
  out.push(node.val)
  inorder(node.right, out)

-> postorder(node, out)
  if node == nil
    return
  postorder(node.left, out)
  postorder(node.right, out)
  out.push(node.val)

-> levelorder(root)
  out = []
  q = [root]
  while !q.empty?
    curr = q.shift
    out.push(curr.val)
    if curr.left != nil
      q.push(curr.left)
    if curr.right != nil
      q.push(curr.right)
  out

#         1
#        / \
#       2   3
#      / \ /
#     4  5 6
#    /    / \
#   7    8   9
n7 = TreeNode.new(7, nil, nil)
n4 = TreeNode.new(4, n7, nil)
n5 = TreeNode.new(5, nil, nil)
n2 = TreeNode.new(2, n4, n5)
n8 = TreeNode.new(8, nil, nil)
n9 = TreeNode.new(9, nil, nil)
n6 = TreeNode.new(6, n8, n9)
n3 = TreeNode.new(3, n6, nil)
root = TreeNode.new(1, n2, n3)

pre = []
preorder(root, pre)
ino = []
inorder(root, ino)
post = []
postorder(root, post)
lvl = levelorder(root)

pre_s = pre.join(" ")
ino_s = ino.join(" ")
post_s = post.join(" ")
lvl_s = lvl.join(" ")

<< "preorder:   [pre_s]"
<< "inorder:    [ino_s]"
<< "postorder:  [post_s]"
<< "levelorder: [lvl_s]"

## expect stdout
## preorder:   1 2 4 7 5 3 6 8 9
## inorder:    7 4 2 5 1 8 6 9 3
## postorder:  7 4 5 2 8 9 6 3 1
## levelorder: 1 2 3 4 5 6 7 8 9
