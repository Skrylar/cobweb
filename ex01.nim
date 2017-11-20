
import json
import cobweb
import math

var cob = make_cobweb()
cob["cupcakes"] = % 5
cob["danishes"] = % 7

assert cob["cupcakes"].getNum == 5
assert cob["danishes"].getNum == 7

cob.dependent delicious do(cupcakes, danishes):
  # NB it would also be allowed to change the result in-place, to conserve allocations
  delicious = % (max(cupcakes.getnum(0), danishes.getnum(0)) * 2)
  return true
