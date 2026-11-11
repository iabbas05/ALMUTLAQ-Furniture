'use strict';
const $ = id => document.getElementById(id);
let state, catalogue = [], categories = [], csrf, active = 0, drag = false, scale = 1, origin = {x:0,y:0};
const canvas = $('plan'), ctx = canvas.getContext('2d');
const roomPreview = new MeasuredRoomPreview($('room-3d'), path => api(path));
const copy = value => JSON.parse(JSON.stringify(value));
function notify(text, error = false) { $('message').textContent = text; $('message').className = error ? 'error' : ''; }
async function api(path, data, options = {}) {
  const response = await fetch(path, {
    method: data === undefined ? 'GET' : 'POST',
    headers: {'Content-Type':'application/json', ...(csrf ? {'X-Showroom-CSRF':csrf} : {}), ...(options.headers || {})},
    ...(data === undefined ? {} : {body: options.binary ? data : JSON.stringify(data)}),
    credentials: 'same-origin',
  });
  const result = await response.json();
  if (!response.ok) throw new Error(result.error || 'تعذر تنفيذ الطلب');
  return result;
}
function run(action) { return async event => { event?.preventDefault(); try { await action(); } catch (error) { notify(error.message, true); } }; }
function option(value, text) { const element = document.createElement('option'); element.value = value; element.textContent = text; return element; }
function button(text, action, className = '') {
  const b = document.createElement('button'); b.type='button'; b.textContent=text; b.className=className;
  b.addEventListener('click', run(action)); return b;
}
function productFor(item) { return catalogue.find(p => p.id === item.productId); }
function selected() { return state?.items[active]; }
function footprint(item) {
  const p = productFor(item), t = item.rotationY * Math.PI / 180;
  return {x:(Math.abs(Math.cos(t))*p.dimensions.width + Math.abs(Math.sin(t))*p.dimensions.depth)/2,
          z:(Math.abs(Math.sin(t))*p.dimensions.width + Math.abs(Math.cos(t))*p.dimensions.depth)/2};
}
function contain(item) {
  const e = footprint(item);
  if (e.x*2 > state.room.width || e.z*2 > state.room.depth) throw new Error('القطعة ما تناسب الغرفة بهالزاوية');
  item.position.x = Math.max(e.x,Math.min(state.room.width-e.x,item.position.x));
  item.position.z = Math.max(e.z,Math.min(state.room.depth-e.z,item.position.z));
}
function status(value) {
  $('revision').textContent = 'Revision '+value.revision;
  const applied = value.appliedRevision === value.revision;
  $('connection').textContent = applied ? 'النظارة أكدت تطبيق التصميم' : 'بانتظار تأكيد النظارة';
  if (applied && value.headsetSeenSecondsAgo != null && value.headsetSeenSecondsAgo > 10) $('connection').textContent = 'آخر تصميم مؤكد، النظارة ما ردّت مؤخرًا';
}
async function send(next) {
  const result = await api('/api/state', {...next, expectedRevision:state.revision});
  state = result; render(); status(result);
}
async function refresh() {
  const [next, products] = await Promise.all([api('/api/state'),api('/api/catalogue')]);
  catalogue = products.products; categories = products.categories; state = next;
  render(); renderCatalogue(); status(next);
}
function draw() {
  if (!state) return;
  const w = canvas.width, h = canvas.height;
  ctx.clearRect(0,0,w,h); ctx.fillStyle='#eeebe4'; ctx.fillRect(0,0,w,h);
  scale = Math.min((w-100)/state.room.width,(h-100)/state.room.depth);
  origin = {x:(w-state.room.width*scale)/2,y:(h-state.room.depth*scale)/2};
  ctx.save(); ctx.translate(origin.x,origin.y); ctx.scale(scale,scale);
  const rw=state.room.width, rd=state.room.depth;
  ctx.fillStyle='#dfc9a7'; ctx.fillRect(0,0,rw,rd);
  ctx.strokeStyle='#c9ae86'; ctx.lineWidth=1/scale;
  for(let z=0;z<rd;z+=.22){ctx.beginPath();ctx.moveTo(0,z);ctx.lineTo(rw,z);ctx.stroke();}
  ctx.strokeStyle='#514c42'; ctx.lineWidth=7/scale; ctx.strokeRect(0,0,rw,rd);
  for(const o of state.openings){
    const horizontal=['top','bottom'].includes(o.wall);
    const x=o.wall==='right'?rw:o.wall==='left'?0:o.offset;
    const z=o.wall==='bottom'?rd:o.wall==='top'?0:o.offset;
    ctx.strokeStyle=o.kind==='window'?'#5a97a4':'#dfc9a7';ctx.lineWidth=10/scale;
    ctx.beginPath();ctx.moveTo(x,z);ctx.lineTo(x+(horizontal?o.width:0),z+(horizontal?0:o.width));ctx.stroke();
    if(o.kind==='door'){
      const hingeX=x+(horizontal&&o.reverse?o.width:0), hingeZ=z+(!horizontal&&o.reverse?o.width:0);
      const normal = o.wall==='top'?{x:0,z:1}:o.wall==='bottom'?{x:0,z:-1}:o.wall==='left'?{x:1,z:0}:{x:-1,z:0};
      ctx.strokeStyle='#8a7359';ctx.lineWidth=1.5/scale;
      ctx.beginPath();ctx.moveTo(hingeX,hingeZ);ctx.lineTo(hingeX+normal.x*o.width,hingeZ+normal.z*o.width);ctx.stroke();
    }
  }
  state.items.forEach((item,i)=>{
    const p=productFor(item); if(!p)return;
    ctx.save();ctx.translate(item.position.x,item.position.z);ctx.rotate(item.rotationY*Math.PI/180);
    const pw=p.dimensions.width,pd=p.dimensions.depth, chair=pw<1.2, arms=chair?.14:.24;
    ctx.fillStyle='#b29d8055';ctx.beginPath();ctx.roundRect(-pw/2+.03,-pd/2+.04,pw,pd,.09);ctx.fill();
    ctx.fillStyle='#c9bba3';ctx.beginPath();ctx.roundRect(-pw/2,-pd/2,pw,pd,.09);ctx.fill();
    ctx.fillStyle='#e7ddcb';ctx.beginPath();ctx.roundRect(-pw/2+.04,-pd/2+.03,pw-.08,pd*.25,.07);ctx.fill();
    const seats=chair?1:3, inside=pw-2*arms;
    ctx.fillStyle='#f3ead8';
    for(let n=0;n<seats;n++){ctx.beginPath();ctx.roundRect(-inside/2+n*inside/seats+.012,-pd*.18,inside/seats-.024,pd*.62,.055);ctx.fill();}
    ctx.fillStyle='#e5d6bd';
    for(const x of [-pw/2,pw/2-arms]){ctx.beginPath();ctx.roundRect(x,-pd*.35,arms,pd*.83,.065);ctx.fill();}
    if(i===active){ctx.strokeStyle='#24664e';ctx.lineWidth=3/scale;ctx.setLineDash([.05,.035]);ctx.strokeRect(-pw/2-.035,-pd/2-.035,pw+.07,pd+.07);}
    ctx.restore();
  });
  ctx.restore();
  ctx.fillStyle='#4d5d51';ctx.font='20px Segoe UI';ctx.textAlign='center';
  ctx.fillText(state.room.width.toFixed(2)+' m',w/2,origin.y-16);
  ctx.save();ctx.translate(origin.x-24,h/2);ctx.rotate(-Math.PI/2);ctx.fillText(state.room.depth.toFixed(2)+' m',0,0);ctx.restore();
  const piece=selected();
  if(piece){const e=footprint(piece), x=piece.position.x,z=piece.position.z;
    $('gaps').textContent='يسار '+(x-e.x).toFixed(2)+' م · أعلى '+(z-e.z).toFixed(2)+' م · يمين '+(state.room.width-x-e.x).toFixed(2)+' م · أسفل '+(state.room.depth-z-e.z).toFixed(2)+' م';}
  else $('gaps').textContent='';
}
function render() {
  for(const axis of ['width','depth','height'])$(axis).value=state.room[axis];
  active=Math.max(0,Math.min(active,state.items.length-1));
  $('pieces').replaceChildren(...state.items.map((item,i)=>option(i,(i+1)+'. '+(productFor(item)?.arabic||item.productId))));
  $('pieces').value=active;
  $('rotate').disabled=$('remove').disabled=!state.items.length;
  $('products').replaceChildren(...catalogue.filter(p=>p.status==='published').map(p=>{
    const b=button(p.arabic,async()=>{
      const next=copy(state), item={instanceId:crypto.randomUUID(),productId:p.id,modelVersion:p.modelVersion,position:{x:state.room.width/2,z:state.room.depth/2},rotationY:0};
      contain(item);next.items.push(item);active=next.items.length-1;await send(next);
    });
    const small=document.createElement('small');small.textContent=p.dimensions.width+' × '+p.dimensions.depth+' م';b.append(small);return b;
  }));
  $('openings').replaceChildren(...state.openings.map((o,i)=>{
    const row=document.createElement('div');row.className='opening-row';
    const text=document.createElement('span');text.textContent=(o.kind==='window'?'دريشة':'باب')+' · '+o.width+' م';row.append(text,button('حذف',async()=>{const next=copy(state);next.openings.splice(i,1);await send(next);},'subtle'));return row;
  }));
  draw();
  if ($('room-preview').open) roomPreview.update(state, catalogue).catch(e=>notify(e.message,true));
}
$('room-preview').addEventListener('toggle',()=>{if($('room-preview').open&&state)roomPreview.update(state,catalogue).catch(e=>notify(e.message,true));});
function selectProduct(id){
  const p=catalogue.find(p=>p.id===id);if(!p)return;
  for(const [key,value] of Object.entries({id:p.id,name:p.name,arabic:p.arabic,width:p.dimensions.width,depth:p.dimensions.depth,height:p.dimensions.height}))$('product-'+key).value=value;
  $('product-category').value=p.category;$('model-product').value=p.id;modelStatus();$('visual-approval').checked=false;
}
function modelStatus(){
  const p=catalogue.find(p=>p.id===$('model-product').value);
  $('model-status').textContent=p?(p.status==='published'?'نسخة منشورة':'مسودة')+(p.draftVersion?' · توجد مسودة مجسم':''):'اختار منتجًا';
}
function renderCatalogue(){
  const current=$('model-product').value;
  $('product-category').replaceChildren(...categories.map(c=>option(c.id,c.name)));
  $('model-product').replaceChildren(...catalogue.map(p=>option(p.id,p.arabic)));
  if(catalogue.some(p=>p.id===current))$('model-product').value=current;
  $('catalogue-list').replaceChildren(...catalogue.map(p=>{
    const row=document.createElement('div');row.className='catalogue-row';
    const text=document.createElement('p');text.textContent=p.arabic+' · '+p.sku+' · '+(p.status==='published'?'منشور':'بانتظار مجسم');
    row.append(text,button('تعديل',()=>selectProduct(p.id)));return row;
  }));modelStatus();
}
async function customers(){
  const policy=await api('/api/privacy');$('retention-days').value=policy.retentionDays;
  const value=await api('/api/customers?q='+encodeURIComponent($('customer-search').value));
  $('customer-list').replaceChildren(...value.customers.map(c=>{
    const row=document.createElement('article');row.className='customer-row';
    const label=document.createElement('div'), name=document.createElement('p'), phone=document.createElement('p');
    name.textContent=c.name;phone.textContent=c.phone;phone.dir='ltr';label.append(name,phone);
    const actions=document.createElement('div');actions.className='actions';
    actions.append(button('تصدير',async()=>{
      const value=await api('/api/export-customer',{id:c.id});
      const url=URL.createObjectURL(new Blob([JSON.stringify(value,null,2)],{type:'application/json'}));
      const link=document.createElement('a');link.href=url;link.download='customer-design-'+c.id+'.json';
      link.click();setTimeout(()=>URL.revokeObjectURL(url),1000);
    }),button('فتح التجربة',async()=>{
      state=await api('/api/restore-customer',{id:c.id,expectedRevision:state.revision});render();switchTab('room');status(state);notify('انفتحت التجربة، بانتظار تأكيد النظارة');
    }),button('حذف',async()=>{
      if(!confirm('تحذف بيانات هالعميل والتصميم المحفوظ؟'))return;
      await api('/api/delete-customer',{id:c.id});await customers();
    },'subtle'));row.append(label,actions);return row;
  }));
  if(!value.customers.length)$('customer-list').textContent='ما في تجارب مطابقة';
}
function switchTab(id){
  for(const section of document.querySelectorAll('.tab'))section.hidden=section.id!==id;
  for(const b of document.querySelectorAll('nav button'))b.setAttribute('aria-current',b.dataset.tab===id?'page':'false');
  if(id==='customers')customers().catch(e=>notify(e.message,true));
}
for(const b of document.querySelectorAll('nav button'))b.addEventListener('click',()=>switchTab(b.dataset.tab));
$('measurements').addEventListener('submit',run(async()=>{
  const next=copy(state);for(const a of ['width','depth','height'])next.room[a]=Number($(a).value);await send(next);
}));
$('pieces').addEventListener('change',()=>{active=Number($('pieces').value);draw();});
$('rotate').addEventListener('click',run(async()=>{if(!selected())return;const next=copy(state);next.items[active].rotationY=(next.items[active].rotationY+15)%360;contain(next.items[active]);await send(next);}));
$('remove').addEventListener('click',run(async()=>{const next=copy(state);next.items.splice(active,1);await send(next);}));
$('opening-form').addEventListener('submit',run(async()=>{
  const next=copy(state),kind=$('opening-kind').value;
  next.openings.push({kind,wall:$('opening-wall').value,offset:Number($('opening-offset').value),width:Number($('opening-width').value),
    height:Number($('opening-height').value),sill:kind==='door'?0:Number($('opening-sill').value),reverse:$('opening-reverse').checked});
  await send(next);
}));
$('pair').addEventListener('click',run(async()=>{const value=await api('/api/pairing',{});$('pair-code').textContent=value.code;}));
$('revoke').addEventListener('click',run(async()=>{if(confirm('تلغي ربط كل أجهزة التجربة؟')){await api('/api/revoke-devices',{});notify('انلغى ربط الأجهزة');}}));
$('import').addEventListener('click',run(async()=>{const data=JSON.parse($('room-json').value);await send(data);}));
$('new-session').addEventListener('click',run(async()=>{
  if(!confirm('تبدأ تجربة جديدة وتخلي الغرفة الحالية فاضية؟'))return;
  state=await api('/api/new-session',{...state,items:[],openings:[],expectedRevision:state.revision});render();status(state);
}));
$('save-customer').addEventListener('submit',run(async()=>{
  await api('/api/customers',{name:$('customer-name').value,phone:$('customer-phone').value,consent:$('customer-consent').checked});
  $('save-customer').reset();notify('انحفظت التجربة على هالكمبيوتر');
}));
$('customer-search').addEventListener('input',()=>customers().catch(e=>notify(e.message,true)));
$('privacy-form').addEventListener('submit',run(async()=>{
  if(!confirm('بتنحذف التجارب الأقدم من المدة الجديدة. تبي تحفظها؟'))return;
  await api('/api/privacy',{retentionDays:Number($('retention-days').value)});await customers();notify('انحفظت مدة الاحتفاظ');
}));
$('category-form').addEventListener('submit',run(async()=>{
  await api('/api/categories',{id:$('category-id').value,name:$('category-name').value});await refresh();notify('انحفظ التصنيف');
}));
$('product-form').addEventListener('submit',run(async()=>{
  await api('/api/products',{id:$('product-id').value,name:$('product-name').value,arabic:$('product-arabic').value,category:$('product-category').value,
    dimensions:{width:Number($('product-width').value),depth:Number($('product-depth').value),height:Number($('product-height').value)}});
  const id=$('product-id').value;await refresh();selectProduct(id);notify('انحفظت بيانات المنتج');
}));
$('model-product').addEventListener('change',()=>{modelStatus();$('visual-approval').checked=false;});
$('upload-model').addEventListener('click',run(async()=>{
  const file=$('model-file').files[0];if(!file||!file.name.toLowerCase().endsWith('.glb'))throw new Error('اختار ملف GLB');
  if(file.size>15*1024*1024)throw new Error('حجم الملف أكبر من ١٥ ميغابايت');
  await api('/api/upload-model?id='+encodeURIComponent($('model-product').value),file,{binary:true,headers:{'Content-Type':'model/gltf-binary'}});
  await refresh();$('visual-approval').checked=false;notify('انرفعت مسودة المجسم، راجعها قبل النشر');
}));
$('publish-model').addEventListener('click',run(async()=>{
  const p=catalogue.find(p=>p.id===$('model-product').value);if(!p)throw new Error('اختار منتجًا');
  await api('/api/publish',{id:p.id,modelVersion:p.draftVersion||p.modelVersion,visuallyApproved:$('visual-approval').checked});
  await refresh();notify('اننشرت النسخة، التصميم المفتوح احتفظ بنسخته السابقة');
}));
$('close-preview').addEventListener('click',()=>$('model-dialog').close());
$('preview-model').addEventListener('click',run(async()=>{
  const p=catalogue.find(p=>p.id===$('model-product').value);if(!p)throw new Error('اختار منتجًا');
  const meta=p.versions[p.draftVersion||p.modelVersion];if(!meta)throw new Error('ارفع مجسمًا أولًا');
  const mesh=await api(meta.modelUrl);
  previewMesh(mesh);$('model-dialog').showModal();
}));
function previewMesh(mesh){
  const c=$('model-canvas'),g=c.getContext('2d'),faces=[];
  g.clearRect(0,0,c.width,c.height);
  const yaw=.65,e=.55,cs=Math.cos(yaw),sn=Math.sin(yaw),fit=Math.min(700/(mesh.width+mesh.depth),460/(mesh.height+mesh.depth*.6));
  const screen=p=>[c.width/2+(p[0]*cs-p[2]*sn)*fit,c.height*.78+((p[0]*sn+p[2]*cs)*Math.sin(e)-p[1]*Math.cos(e))*fit];
  for(const part of mesh.parts){
    const v=part.vertices;
    for(let i=0;i<part.triangles.length;i+=3){
      const points=part.triangles.slice(i,i+3).map(n=>v.slice(n*3,n*3+3));
      const a=points[0],b=points[1],d=points[2],u=b.map((x,n)=>x-a[n]),vv=d.map((x,n)=>x-a[n]);
      const normal=[u[1]*vv[2]-u[2]*vv[1],u[2]*vv[0]-u[0]*vv[2],u[0]*vv[1]-u[1]*vv[0]],len=Math.hypot(...normal)||1;
      const light=.68+.32*Math.max(0,(normal[1]-.4*normal[0]-.25*normal[2])/len);
      const color=part.color.slice(0,3).map(x=>Math.round(Math.pow(x,1/2.2)*255*light));
      faces.push({points:points.map(screen),depth:points.reduce((sum,p)=>sum+(p[0]*sn+p[2]*cs)*Math.cos(e)+p[1]*Math.sin(e),0)/3,color});
    }
  }
  faces.sort((a,b)=>a.depth-b.depth);
  for(const face of faces){g.fillStyle='rgb('+face.color.join(',')+')';g.beginPath();face.points.forEach((p,i)=>i?g.lineTo(...p):g.moveTo(...p));g.closePath();g.fill();}
}
function locationAt(event){
  const r=canvas.getBoundingClientRect();
  return {x:((event.clientX-r.left)*canvas.width/r.width-origin.x)/scale,z:((event.clientY-r.top)*canvas.height/r.height-origin.y)/scale};
}
canvas.addEventListener('pointerdown',event=>{
  if(!state)return;const p=locationAt(event);
  for(let i=state.items.length-1;i>=0;i--){
    const item=state.items[i],product=productFor(item);if(!product)continue;
    const t=item.rotationY*Math.PI/180,dx=p.x-item.position.x,dz=p.z-item.position.z;
    if(Math.abs(dx*Math.cos(t)+dz*Math.sin(t))<=product.dimensions.width/2 &&
       Math.abs(-dx*Math.sin(t)+dz*Math.cos(t))<=product.dimensions.depth/2){
      active=i;drag=true;canvas.setPointerCapture(event.pointerId);draw();break;
    }
  }
});
canvas.addEventListener('pointermove',event=>{
  if(!drag||!selected())return;const p=locationAt(event);selected().position=p;
  try{contain(selected());draw();}catch(error){notify(error.message,true);}
});
async function finishDrag(){
  if(!drag)return;drag=false;
  try{await send(copy(state));}catch(error){notify(error.message,true);await refresh();}
}
canvas.addEventListener('pointerup',finishDrag);canvas.addEventListener('pointercancel',finishDrag);
async function start(){
  const bootstrap=await api('/api/bootstrap');csrf=bootstrap.csrf;await refresh();
  setInterval(async()=>{try{
    const value=await api('/api/status');status(value);
    if(!drag&&value.revision!==state.revision)await refresh();
  }catch(_){$('connection').textContent='الاتصال مقطوع، التصميم محفوظ';}},1000);
}
start().catch(error=>notify(error.message,true));
