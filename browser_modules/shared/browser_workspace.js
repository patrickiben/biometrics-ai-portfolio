(function () {
  'use strict';
  let generation = 0;
  const encoder = new TextEncoder();
  function state(value, active) {
    document.body.dataset.bwState = value;
    document.querySelector('#bw_export').disabled = !active;
    for (const node of document.body.children) if (node.id !== 'bw_workspace' && !['SCRIPT','STYLE','LINK'].includes(node.tagName)) {
      node.inert = !active;
      if (!active) node.setAttribute('aria-hidden','true'); else node.removeAttribute('aria-hidden');
    }
    if (!active) document.querySelector('#bw_setup').open = true;
  }
  function send(action, fresh) {
    if (fresh) { generation += 1; state('empty',false); }
    Shiny.setInputValue('bw_action',{action,generation,nonce:Date.now()},{priority:'event'});
  }
  document.addEventListener('click',function(event) {
    const button = event.target.closest('#bw_example,#bw_reset,#bw_apply,#bw_templates,#bw_export,#bw_change');
    if (!button) return;
    event.preventDefault();
    const action = button.id.slice(3);
    if (action === 'change') { document.querySelector('#bw_setup').open = !document.querySelector('#bw_setup').open; return; }
    send(action,action==='reset'||action==='example');
  });
  document.addEventListener('change',async function(event) {
    if (!event.target.matches('#bw_files')) return;
    event.preventDefault();event.stopImmediatePropagation();
    const files=[...event.target.files];if(!files.length)return;
    const current=++generation;state('loading',false);
    Shiny.setInputValue('bw_begin',{generation:current},{priority:'event'});
    try {
      if(files.length>30)throw Error('Select no more than 30 files.');
      const saved=files.length===1&&/\.json$/i.test(files[0].name);
      if(files.some(file=>file.size>(saved?96:16)*1024*1024))throw Error(saved?'A saved workspace may be at most 96 MiB.':'Each CSV must be at most 16 MiB.');
      if(files.reduce((sum,file)=>sum+file.size,0)>(saved?96:32)*1024*1024)throw Error('Combined CSV files must be at most 32 MiB.');
      const values=await Promise.all(files.map(async file=>({name:file.name,text:new TextDecoder('utf-8',{fatal:true}).decode(await file.arrayBuffer())})));
      if(current===generation)Shiny.setInputValue('bw_payload',{generation:current,files:values},{priority:'event'});
    }catch(error){if(current===generation)Shiny.setInputValue('bw_payload',{generation:current,error:String(error.message)},{priority:'event'});}
    event.target.value='';
  },true);
  const crcTable=new Uint32Array(256);
  for(let i=0;i<256;i++){let value=i;for(let j=0;j<8;j++)value=(value&1)?(0xedb88320^(value>>>1)):(value>>>1);crcTable[i]=value>>>0;}
  function crc32(data){let crc=0xffffffff;for(const byte of data)crc=crcTable[(crc^byte)&255]^(crc>>>8);return(crc^0xffffffff)>>>0;}
  function zip(files){
    const local=[],central=[];let offset=0,centralSize=0;
    if(!files.length||files.length>65535)throw Error('Unsupported export file count.');
    for(const file of files){
      if(typeof file.content!=="string")throw Error("Export content must be text.");
      if(!file.name||/(^\/|\\|(^|\/)\.\.(\/|$)|[\x00-\x1f])/.test(file.name))throw Error('Invalid export filename.');
      const name=encoder.encode(file.name),data=encoder.encode(file.content),crc=crc32(data);
      if(name.length>65535||offset+data.length>0xffffffff)throw Error('Export exceeds ZIP limits.');
      const header=new Uint8Array(30),h=new DataView(header.buffer);
      h.setUint32(0,0x04034b50,true);h.setUint16(4,20,true);h.setUint16(6,0x800,true);h.setUint16(12,0x21,true);
      h.setUint32(14,crc,true);h.setUint32(18,data.length,true);h.setUint32(22,data.length,true);h.setUint16(26,name.length,true);
      local.push(header,name,data);
      const directory=new Uint8Array(46),d=new DataView(directory.buffer);
      d.setUint32(0,0x02014b50,true);d.setUint16(4,20,true);d.setUint16(6,20,true);d.setUint16(8,0x800,true);d.setUint16(14,0x21,true);
      d.setUint32(16,crc,true);d.setUint32(20,data.length,true);d.setUint32(24,data.length,true);d.setUint16(28,name.length,true);d.setUint32(42,offset,true);
      central.push(directory,name);centralSize+=directory.length+name.length;offset+=header.length+name.length+data.length;
    }
    const end=new Uint8Array(22),e=new DataView(end.buffer);e.setUint32(0,0x06054b50,true);e.setUint16(8,files.length,true);e.setUint16(10,files.length,true);e.setUint32(12,centralSize,true);e.setUint32(16,offset,true);
    return new Blob([...local,...central,end],{type:'application/zip'});
  }
  function connect(){
    if(!window.Shiny){setTimeout(connect,25);return;}
    Shiny.addCustomMessageHandler('bw-state',function(message){
      if(message.generation<generation)return;
      generation=message.generation;state(message.state,message.active);
      if(message.active)document.querySelector('#bw_setup').open=false;
    });
    Shiny.addCustomMessageHandler('bw-file',function(message){
      if(message.generation!==generation)return;
      const url=URL.createObjectURL(new Blob([message.content],{type:message.type})),link=document.createElement('a');link.href=url;link.download=message.filename;document.body.appendChild(link);link.click();
      setTimeout(()=>{URL.revokeObjectURL(url);link.remove();},1000);
    });
    Shiny.addCustomMessageHandler('bw-download',function(message){
      if(message.generation!==generation)return;
      const url=URL.createObjectURL(zip(message.files)),link=document.createElement('a');link.href=url;link.download=message.filename;document.body.appendChild(link);link.click();
      setTimeout(()=>{URL.revokeObjectURL(url);link.remove();},1000);
    });
    if(document.body&&document.querySelector('#bw_workspace'))state('empty',false);
  }
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',connect);else connect();
})();
