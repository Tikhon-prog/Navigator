"use strict";
(function(){
const screens=[...document.querySelectorAll("[data-screen]")];
const tabs=[...document.querySelectorAll("[data-tab]")];
const dialog=document.getElementById("install-dialog");
function activate(name){
 if(!screens.some(s=>s.dataset.screen===name))name="home";
 screens.forEach(s=>{const on=s.dataset.screen===name;s.hidden=!on;s.classList.toggle("active",on);});
 tabs.forEach(b=>{const on=b.dataset.tab===name;b.classList.toggle("active",on);if(on)b.setAttribute("aria-current","page");else b.removeAttribute("aria-current");});
 if(history.replaceState)history.replaceState(null,"","#"+name);
 window.scrollTo({top:0,behavior:"smooth"});
}
document.addEventListener("click",e=>{
 const t=e.target.closest("[data-tab]"),g=e.target.closest("[data-go]");
 if(t)activate(t.dataset.tab);
 if(g)activate(g.dataset.go);
});
const now=new Date();
document.getElementById("date-day").textContent=String(now.getDate()).padStart(2,"0");
document.getElementById("date-month").textContent=new Intl.DateTimeFormat("ru-RU",{month:"short"}).format(now).replace(".","");
document.getElementById("today").textContent=new Intl.DateTimeFormat("ru-RU",{weekday:"long",day:"numeric",month:"long"}).format(now).toLocaleUpperCase("ru-RU");
function standalone(){return navigator.standalone===true||matchMedia("(display-mode: standalone)").matches;}
function ios(){return /iphone|ipad|ipod/i.test(navigator.userAgent)||(navigator.platform==="MacIntel"&&navigator.maxTouchPoints>1);}
function showInstall(){if(dialog&&dialog.showModal)dialog.showModal();else alert("В Safari нажми «Поделиться» → «На экран Домой» → «Добавить».");}
document.getElementById("install").addEventListener("click",showInstall);
document.getElementById("show-install").addEventListener("click",showInstall);
document.getElementById("close-dialog").addEventListener("click",()=>dialog.close());
document.getElementById("done-dialog").addEventListener("click",()=>dialog.close());
document.getElementById("hide-hint").addEventListener("click",()=>{document.getElementById("install-hint").hidden=true;});
if(standalone()){document.getElementById("install").hidden=true;document.getElementById("install-hint").hidden=true;}
else if(ios()){document.getElementById("install-hint").hidden=false;}
const apiConfigured=Boolean(window.POKOLENIE_API_BASE_URL);
document.getElementById("connection").textContent=apiConfigured?"API настроен":"Локальный режим";
activate(location.hash.slice(1)||"home");
})();