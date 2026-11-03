(function(){
'use strict';
const state = window.methodApp = {epoch:0,lastDownload:null};
function changed(target){const confirm=document.getElementById('confirmed');if(target?.id!=='confirmed'&&confirm?.checked){confirm.checked=false;confirm.dispatchEvent(new Event('change',{bubbles:true}));}state.epoch++;document.documentElement.classList.add('method-dirty');document.querySelectorAll('#run,.method-export').forEach(x=>x.disabled=true);Shiny.setInputValue('form_epoch',state.epoch,{priority:'event'});}
for(const name of ['input','change'])document.addEventListener(name,e=>{if(e.target.closest('.method-config'))changed(e.target)});
document.addEventListener('click',e=>{if(e.target.closest('#reset,#cqtc_full'))changed(e.target)});
Shiny.addCustomMessageHandler('method-ready',m=>{if(m.epoch===state.epoch)document.documentElement.classList.remove('method-dirty')});
$(document).on('shiny:connected',()=>{let module;try{module=new URL(window.parent.location.href).searchParams.get('module')}catch(e){}if(module)Shiny.setInputValue('method_request',module,{priority:'event'})});
  function bytes(encoded) {
    const raw = atob(encoded), out = new Uint8Array(raw.length);
    for (let i=0; i<raw.length; i++) out[i] = raw.charCodeAt(i);
    return out;
  }
  const crcTable = new Uint32Array(256);
  for (let i=0; i<256; i++) {
    let value = i;
    for (let j=0; j<8; j++) value = (value & 1) ? (0xedb88320 ^ (value >>> 1)) : (value >>> 1);
    crcTable[i] = value >>> 0;
  }
  function crc32(data) {
    let crc = 0xffffffff;
    for (let i=0; i<data.length; i++) crc = crcTable[(crc ^ data[i]) & 255] ^ (crc >>> 8);
    return (crc ^ 0xffffffff) >>> 0;
  }
  // ZIP store method: no native zip executable, third-party library or network.
  // UTF-8 names, CRC-32, 32-bit sizes; the R caller bounds the bundle to 50 MiB.
  function zip(files) {
    const local = [], central = [], encoder = new TextEncoder();
    let offset = 0, centralSize = 0;
    if (!files.length || files.length > 65535) throw new Error('Unsupported export file count.');
    for (const item of files) {
      if (!item.name || /(^\/|\\|(^|\/)\.\.(\/|$)|[\x00-\x1f])/.test(item.name)) throw new Error('Invalid export filename.');
      const name = encoder.encode(item.name), data = bytes(item.base64), crc = crc32(data);
      if (name.length > 65535 || offset + data.length > 0xffffffff) throw new Error('Export exceeds ZIP limits.');
      const header = new Uint8Array(30), h = new DataView(header.buffer);
      h.setUint32(0,0x04034b50,true);h.setUint16(4,20,true);h.setUint16(6,0x800,true);h.setUint16(12,0x21,true);
      h.setUint32(14,crc,true);h.setUint32(18,data.length,true);h.setUint32(22,data.length,true);h.setUint16(26,name.length,true);
      local.push(header,name,data);
      const directory = new Uint8Array(46), d = new DataView(directory.buffer);
      d.setUint32(0,0x02014b50,true);d.setUint16(4,20,true);d.setUint16(6,20,true);d.setUint16(8,0x800,true);d.setUint16(14,0x21,true);
      d.setUint32(16,crc,true);d.setUint32(20,data.length,true);d.setUint32(24,data.length,true);d.setUint16(28,name.length,true);d.setUint32(42,offset,true);
      central.push(directory,name);centralSize += directory.length + name.length;offset += header.length + name.length + data.length;
    }
    const end = new Uint8Array(22), e = new DataView(end.buffer);
    e.setUint32(0,0x06054b50,true);e.setUint16(8,files.length,true);e.setUint16(10,files.length,true);e.setUint32(12,centralSize,true);e.setUint32(16,offset,true);
    return new Blob([...local,...central,end],{type:'application/zip'});
  }
  Shiny.addCustomMessageHandler('method-download', function (m) {
    if (m.epoch !== state.epoch) return; // A queued old export must never become current.
    try {
      const blob = m.files ? zip(m.files) : new Blob([bytes(m.base64)],{type:m.type});
      const url = URL.createObjectURL(blob), link = document.createElement('a');
      link.href = url;link.download = m.filename;document.body.appendChild(link);link.click();
      setTimeout(()=>{URL.revokeObjectURL(url);link.remove();},1000);
      state.lastDownload = m.filename;
      Shiny.setInputValue('download_finished',{filename:m.filename,event:Date.now()},{priority:'event'});
    } catch(error) {
      Shiny.setInputValue('download_failed',String(error.message),{priority:'event'});
    }
  });
})();
