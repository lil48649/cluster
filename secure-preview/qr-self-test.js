(function () {
 "use strict";
 const status=document.getElementById("result"),target=document.getElementById("qr");
 try {
  const gen=window.qrgen||window.qrcodegen;
  if(!gen||!gen.QrCode)throw new Error("二维码编码脚本未加载");
  const sample="otpauth://totp/QR-TEST:user%40example.invalid?secret=JBSWY3DPEHPK3PXP&issuer=QR-TEST&digits=6&period=30";
  const qr=gen.QrCode.encodeText(sample,gen.QrCode.Ecc.MEDIUM);
  const ns="http://www.w3.org/2000/svg", svg=document.createElementNS(ns,"svg");
  const quiet=4;svg.setAttribute("viewBox","0 0 "+(qr.size+quiet*2)+" "+(qr.size+quiet*2));
  const bg=document.createElementNS(ns,"rect");bg.setAttribute("width","100%");bg.setAttribute("height","100%");bg.setAttribute("fill","#fff");svg.appendChild(bg);
  let pathText="";
  for(let y=0;y<qr.size;y++)for(let x=0;x<qr.size;x++)if(qr.getModule(x,y))pathText+="M"+(x+quiet)+","+(y+quiet)+"h1v1h-1z";
  const dots=document.createElementNS(ns,"path");dots.setAttribute("d",pathText);dots.setAttribute("fill","#183553");svg.appendChild(dots);target.appendChild(svg);
  status.style.color="#14765d";status.textContent="本地二维码组件运行正常";
 }catch(error){status.style.color="#b42318";status.textContent="二维码组件错误："+(error&&error.name||"Unknown")+"（"+String(error&&error.message||"未知错误").slice(0,120)+"）";}
}());