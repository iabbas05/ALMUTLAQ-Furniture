import json, struct
from pathlib import Path

parts = [
    ("Base", [0,.25,0], [2.10,.50,1.03]),
    ("Back", [0,.69,.375], [1.83,.62,.28]),
    *[("Arm", [x,.41,-.03], [.22,.72,.96]) for x in [-.94,.94]],
    *[("Seat cushion", [x,.54,-.095], [.57,.16,.72]) for x in [-.58,0,.58]],
]
vertices = [-.5,-.5,-.5,.5,-.5,-.5,.5,.5,-.5,-.5,.5,-.5,-.5,-.5,.5,.5,-.5,.5,.5,.5,.5,-.5,.5,.5]
indices = [0,2,1,0,3,2,4,5,6,4,6,7,0,4,7,0,7,3,1,2,6,1,6,5,0,1,5,0,5,4,3,7,6,3,6,2]
data = struct.pack('<24f36H', *vertices, *indices)
model = dict(
    asset={'version':'2.0'}, scene=0, scenes=[{'nodes':list(range(len(parts)))}],
    nodes=[dict(name=name,translation=position,scale=size,mesh=0) for name,position,size in parts],
    meshes=[{'primitives':[dict(attributes={'POSITION':0},indices=1,material=0)]}],
    materials=[{'name':'Approximate white upholstery','pbrMetallicRoughness':{'baseColorFactor':[.86,.81,.72,1],'metallicFactor':0,'roughnessFactor':.95}}],
    buffers=[{'byteLength':len(data)}],
    bufferViews=[dict(buffer=0,byteLength=96,target=34962),dict(buffer=0,byteOffset=96,byteLength=72,target=34963)],
    accessors=[dict(bufferView=0,componentType=5126,count=8,type='VEC3',min=[-.5]*3,max=[.5]*3),dict(bufferView=1,componentType=5123,count=36,type='SCALAR',min=[0],max=[7])],
)
dimensions = [max(p[i]+s[i]/2 for _,p,s in parts)-min(p[i]-s[i]/2 for _,p,s in parts) for i in range(3)]
assert [round(n,2) for n in dimensions] == [2.10,1.00,1.03]
header = json.dumps(model,separators=(',',':')).encode()
header += b' ' * (-len(header)%4)
result = struct.pack('<4sII',b'glTF',2,28+len(header)+len(data))
result += struct.pack('<I4s',len(header),b'JSON')+header
result += struct.pack('<I4s',len(data),b'BIN\0')+data
Path(__file__).with_name('london-10_14_3.glb').write_bytes(result)
