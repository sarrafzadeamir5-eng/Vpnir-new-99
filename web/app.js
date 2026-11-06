const API = "https://qsgnkjiqiwvpnrekyofk.supabase.co/functions/v1/vpnir-api";
const $ = (id) => document.getElementById(id);
const tokenKey = "vpnir_session";
let token = sessionStorage.getItem(tokenKey) || "";
let discountPreview = null;
const prices = {france:6000,multi:15000,unlimited:399000,stars:4750,premium:0};
const labels = {france:"VPN فرانسه",multi:"VPN چندکشور",unlimited:"VPN نامحدود",stars:"تلگرام استارز",premium:"درخواست تلگرام پریمیوم"};
const toman = (n) => new Intl.NumberFormat("fa-IR").format(Number(n||0))+" تومان";
function message(id,text,type=""){const el=$(id);el.textContent=text;el.className="notice "+type;}
async function callApi(action,data={},auth=true){
 const headers={"Content-Type":"application/json"};if(auth&&token)headers.Authorization="Bearer "+token;
 const res=await fetch(API,{method:"POST",headers,body:JSON.stringify({action,...data})});
 const result=await res.json().catch(()=>({error:"invalid_response"}));if(!res.ok||result.error)throw new Error(result.error||"request_failed");return result;
}
function showDashboard(show){$("authPanel").classList.toggle("hidden",show);$("dashboard").classList.toggle("hidden",!show);}
function getQuantity(){const s=$("service").value;return s==="unlimited"||s==="premium"?null:Number($("quantity").value);}
function updateQuantity(){
 const s=$("service").value,input=$("quantity");$("quantityField").classList.toggle("hidden",s==="unlimited"||s==="premium");
 if(s==="france"){input.min=5;input.max=100;input.value=Math.max(5,Math.min(100,Number(input.value)||5));}
 if(s==="multi"){input.min=15;input.max=100;input.value=Math.max(15,Math.min(100,Number(input.value)||15));}
 if(s==="stars"){input.min=50;input.max=1000;input.value=Math.max(50,Math.min(1000,Number(input.value)||50));}
 discountPreview=null;updatePrice();
}
function baseAmount(){const s=$("service").value,q=getQuantity();return s==="unlimited"||s==="premium"?prices[s]:prices[s]*(q||0);}
function updatePrice(){const s=$("service").value,base=baseAmount();$("price").textContent=s==="premium"?"استعلام قیمت":toman(discountPreview?.valid?discountPreview.final_amount_toman:base);$("priceHint").textContent=discountPreview?.valid?"تخفیف "+toman(discountPreview.discount_toman)+" اعمال شده.":"مبلغ تقریبی؛ سفارش پس از بررسی مدیر نهایی می‌شود.";}
$("service").addEventListener("change",updateQuantity);$("quantity").addEventListener("input",()=>{discountPreview=null;updatePrice();});$("discount").addEventListener("input",()=>{discountPreview=null;updatePrice();});
$("loginBtn").addEventListener("click",async()=>{
 const telegram_id=$("telegramId").value.trim(),code=$("loginCode").value.trim();$("loginBtn").disabled=true;message("authMessage","در حال بررسی کد...");
 try{const result=await callApi("verify_login",{telegram_id,code},false);token=result.token;sessionStorage.setItem(tokenKey,token);showDashboard(true);message("authMessage","");await loadOrders();}
 catch(e){message("authMessage","ورود انجام نشد. شناسه و کد را بررسی کن و مطمئن شو کد منقضی نشده است.","error");}
 finally{$("loginBtn").disabled=false;}
});
$("checkDiscount").addEventListener("click",async()=>{
 if($("service").value==="premium"){message("orderMessage","برای پریمیوم، قیمت توسط مدیر اعلام می‌شود.");return;}
 if(!$("discount").value.trim()){message("orderMessage","ابتدا کد تخفیف را وارد کن.","error");return;}
 try{const r=await callApi("preview_discount",{service:$("service").value,quantity:getQuantity(),discount_code:$("discount").value.trim()});discountPreview=r.preview;if(!discountPreview?.valid)throw new Error("invalid_discount");updatePrice();message("orderMessage","کد تخفیف معتبر است و اعمال شد.","success");}
 catch(e){discountPreview=null;updatePrice();message("orderMessage","کد تخفیف قابل استفاده نیست.","error");}
});
$("orderBtn").addEventListener("click",async()=>{
 const service=$("service").value,quantity=getQuantity();
 if((service==="france"&&(quantity<5||quantity>100))||(service==="multi"&&(quantity<15||quantity>100))||(service==="stars"&&(quantity<50||quantity>1000))){message("orderMessage","مقدار واردشده خارج از محدوده مجاز است.","error");return;}
 $("orderBtn").disabled=true;message("orderMessage","در حال ثبت سفارش...");
 try{const r=await callApi("create_order",{service,quantity,discount_code:$("discount").value.trim()||null,note:$("note").value.trim()||null});const o=r.order||{};message("orderMessage","سفارش ثبت شد. کد پیگیری: "+(o.tracking_code||"—")+" — مبلغ: "+toman(o.amount_toman)+". نتیجه بررسی از طریق ربات تلگرام اطلاع‌رسانی می‌شود.","success");$("discount").value="";$("note").value="";discountPreview=null;updatePrice();await loadOrders();}
 catch(e){message("orderMessage","ثبت سفارش انجام نشد. اطلاعات را بررسی کن و دوباره تلاش کن.","error");}
 finally{$("orderBtn").disabled=false;}
});
async function loadOrders(){
 try{const r=await callApi("my_orders"),list=$("ordersList");if(!r.orders?.length){list.innerHTML='<p class="muted">هنوز سفارشی ثبت نکرده‌ای.</p>';return;}list.replaceChildren();
 for(const o of r.orders){const item=document.createElement("div");item.className="order-item";const left=document.createElement("div"),name=document.createElement("strong"),meta=document.createElement("small"),status=document.createElement("span");name.textContent=labels[o.service]||o.service;meta.textContent="پیگیری: "+o.tracking_code+" · "+toman(o.amount_toman);status.className="status";status.textContent=({pending:"در انتظار بررسی",awaiting_payment:"در انتظار پرداخت",approved:"تأیید شده",rejected:"رد شده",cancelled:"لغو شده",quoted:"قیمت اعلام شده",awaiting_customer:"در انتظار پاسخ شما"})[o.status]||o.status;left.append(name,meta);item.append(left,status);list.append(item);}
 }catch(e){$("ordersList").textContent="دریافت سوابق ممکن نشد.";}
}
$("refreshBtn").addEventListener("click",loadOrders);$("logoutBtn").addEventListener("click",async()=>{try{await callApi("logout");}catch(e){}token="";sessionStorage.removeItem(tokenKey);showDashboard(false);});
if(token){showDashboard(true);loadOrders();}else{showDashboard(false);}updateQuantity();