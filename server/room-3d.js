'use strict';
// The exact published triangles used by the headset, in metres. No furniture scaling.
class MeasuredRoomPreview {
  constructor(canvas, getModel) {
    this.canvas=canvas;this.getModel=getModel;this.cache=new Map();this.yaw=.65;this.elevation=.65;this.zoom=1;
    let drag;
    canvas.addEventListener('pointerdown',e=>{drag={x:e.clientX,y:e.clientY};canvas.setPointerCapture(e.pointerId);});
    canvas.addEventListener('pointermove',e=>{
      if(!drag)return;
      this.yaw-=(e.clientX-drag.x)*.008;
      this.elevation=Math.max(.18,Math.min(1.35,this.elevation+(e.clientY-drag.y)*.008));
      drag={x:e.clientX,y:e.clientY};this.draw();
    });
    for(const event of ['pointerup','pointercancel'])canvas.addEventListener(event,()=>{drag=null;});
    canvas.addEventListener('wheel',e=>{e.preventDefault();this.zoom=Math.max(.6,Math.min(2,this.zoom*Math.exp(-e.deltaY*.001)));this.draw();},{passive:false});
  }
  async update(state, products) {
    this.state=JSON.parse(JSON.stringify(state));this.products=products;
    const epoch=this.state;
    for(const item of state.items){
      if(this.cache.has(item.modelVersion))continue;
      const p=products.find(p=>p.id===item.productId),meta=p?.versions?.[item.modelVersion];
      if(!meta)throw new Error('نسخة المجسم مو متوفرة');
      const mesh=await this.getModel(meta.modelUrl);
      this.cache.set(item.modelVersion,mesh);
      if(this.state!==epoch)return;
    }
    this.draw();
  }
  draw() {
    if(!this.state)return;
    const {room,items,openings}=this.state,c=this.canvas,g=c.getContext('2d');
    const cs=Math.cos(this.yaw),sn=Math.sin(this.yaw),se=Math.sin(this.elevation),ce=Math.cos(this.elevation);
    const wide=room.width*Math.abs(cs)+room.depth*Math.abs(sn),high=(room.width*Math.abs(sn)+room.depth*Math.abs(cs))*se+room.height*ce;
    const fit=Math.min((c.width-100)/wide,(c.height-100)/high)*this.zoom;
    const screen=p=>[c.width/2+((p[0]-room.width/2)*cs-(p[2]-room.depth/2)*sn)*fit,
      c.height/2+room.height*ce*fit/2+(((p[0]-room.width/2)*sn+(p[2]-room.depth/2)*cs)*se-p[1]*ce)*fit];
    const depth=p=>(p[0]*sn+p[2]*cs)*ce+p[1]*se, faces=[];
    function face(points,color){faces.push({points,color,z:points.reduce((sum,p)=>sum+depth(p),0)/points.length});}
    function panel(a,b,bottom,top,at,color){if(a<b&&bottom<top)face([at(a,bottom),at(b,bottom),at(b,top),at(a,top)],color);}
    g.clearRect(0,0,c.width,c.height);g.fillStyle='#eeebe4';g.fillRect(0,0,c.width,c.height);
    // Back walls only form a cutaway, so the product remains visible from every orbit angle.
    for(const side of [sn>=0?'left':'right',cs>=0?'top':'bottom']){
      const horizontal=['top','bottom'].includes(side),span=horizontal?room.width:room.depth;
      const at=(t,y)=>side==='top'?[t,y,0]:side==='bottom'?[t,y,room.depth]:side==='left'?[0,y,t]:[room.width,y,t];
      let cursor=0;
      for(const o of openings.filter(o=>o.wall===side).sort((a,b)=>a.offset-b.offset)){
        const a=o.offset,b=a+o.width;
        panel(cursor,a,0,room.height,at,'#e9e1d4');panel(a,b,0,o.sill,at,'#e9e1d4');
        panel(a,b,o.sill+o.height,room.height,at,'#e9e1d4');
        panel(a-.035,a,o.sill,o.sill+o.height+.035,at,'#a48761');
        panel(b,b+.035,o.sill,o.sill+o.height+.035,at,'#a48761');
        panel(a,b,o.sill+o.height,o.sill+o.height+.035,at,'#a48761');
        if(o.kind==='window'){
          panel(a,b,o.sill,o.sill+o.height,at,'#a8cbd3');
          panel((a+b)/2-.018,(a+b)/2+.018,o.sill,o.sill+o.height,at,'#a48761');
          panel(a,b,o.sill-.04,o.sill,at,'#a48761');
        }
        cursor=b;
      }
      panel(cursor,span,0,room.height,at,'#e9e1d4');
    }
    for(let z=0;z<room.depth;z+=.22){
      const end=Math.min(room.depth,z+.22);
      face([[0,0,z],[room.width,0,z],[room.width,0,end],[0,0,end]],Math.round(z/.22)%2?'#d4b48a':'#dcbf98');
    }
    for(const item of items){
      const mesh=this.cache.get(item.modelVersion);if(!mesh)continue;
      const angle=item.rotationY*Math.PI/180,ca=Math.cos(angle),sa=Math.sin(angle);
      const at=p=>[item.position.x+p[0]*ca-p[2]*sa,p[1],item.position.z+p[0]*sa+p[2]*ca];
      for(const part of mesh.parts){
        const v=part.vertices;
        for(let i=0;i<part.triangles.length;i+=3){
          const points=part.triangles.slice(i,i+3).map(n=>at(v.slice(n*3,n*3+3)));
          const [a,b,d]=points,u=b.map((v,n)=>v-a[n]),w=d.map((v,n)=>v-a[n]);
          const normal=[u[1]*w[2]-u[2]*w[1],u[2]*w[0]-u[0]*w[2],u[0]*w[1]-u[1]*w[0]],len=Math.hypot(...normal);
          // Runtime winding uses Unity's clockwise convention. Shade with the outward normal.
          if(!len)continue;
          if(normal[0]*sn*ce+normal[2]*cs*ce+normal[1]*se>=0)continue;
          const light=.72+.28*Math.max(0,(-normal[1]+.4*normal[0]+.25*normal[2])/len);
          const color='rgb('+part.color.slice(0,3).map(v=>Math.round(Math.pow(v,1/2.2)*255*light)).join(',')+')';
          face(points,color);
        }
      }
    }
    faces.sort((a,b)=>a.z-b.z);
    for(const f of faces){g.fillStyle=f.color;g.beginPath();f.points.map(screen).forEach((p,i)=>i?g.lineTo(...p):g.moveTo(...p));g.closePath();g.fill();}
    g.fillStyle='#244d40';g.font='20px sans-serif';g.textAlign='center';
    g.fillText(`${room.width.toFixed(2)} × ${room.depth.toFixed(2)} × ${room.height.toFixed(2)} m`,c.width/2,c.height-16);
  }
}
