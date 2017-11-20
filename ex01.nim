
import json
import cobweb

var cob = make_cobweb()
cob["cupcakes"] = % 32

assert cob["cupcakes"].getNum == 32
