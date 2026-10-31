(function(){
"use strict";
var SOURCE="data/gbd2023_low_physical_activity.csv";
var HEADERS=["population_group","measure","location","sex","age","cause","rei","metric","year","val","upper","lower"];
var MEASURES=["Deaths","DALYs (Disability-Adjusted Life Years)","YLLs (Years of Life Lost)","YLDs (Years Lived with Disability)"];
var MNAME={"Deaths":"死亡人数","DALYs (Disability-Adjusted Life Years)":"DALY","YLLs (Years of Life Lost)":"YLL","YLDs (Years Lived with Disability)":"YLD"};
var MFULL={"Deaths":"死亡人数（Deaths）","DALYs (Disability-Adjusted Life Years)":"伤残调整寿命年（DALY）","YLLs (Years of Life Lost)":"早死所致寿命损失年（YLL）","YLDs (Years Lived with Disability)":"伤残所致健康寿命损失年（YLD）"};
var CNAME={"Diabetes mellitus type 2":"2型糖尿病","Ischemic stroke":"缺血性卒中","Ischemic heart disease":"缺血性心脏病"};
var SEX={"Both":"总体","Male":"男性","Female":"女性"};
var COLORS=["#3077da","#21a68a","#ecac57","#9d82d8","#5aa5c0","#d97579"];
var $=function(id){return document.getElementById(id)};
var records=[],page="dashboard",curPage=1,sortKey="year",sortDir=-1,showFav=false,selected=null,toastTimer=null;
var bookmarks=new Set();
try{bookmarks=new Set(JSON.parse(localStorage.getItem("gbd-2023-favorites")||"[]"))}catch(e){}
function saveBookmarks(){try{localStorage.setItem("gbd-2023-favorites",JSON.stringify(Array.from(bookmarks)))}catch(e){}}
function esc(value){return String(value===null||value===undefined?"":value).replace(/[&<>"']/g,function(s){return {"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[s]})}
function fmt(value,digits){var n=Number(value);return Number.isFinite(n)?n.toLocaleString("en-US",{minimumFractionDigits:digits===undefined?2:digits,maximumFractionDigits:digits===undefined?2:digits}):"—"}
function compact(v){var a=Math.abs(v);return a>=1000000?fmt(v/1000000,2)+"百万":a>=10000?fmt(v/10000,2)+"万":fmt(v,2)}
function pct(before,after){return before===0?null:(after-before)/Math.abs(before)*100}
function ptext(value){return value===null?"不可计算":(value>=0?"+":"")+fmt(value,2)+"%"}
function labelCause(c){return CNAME[c]||c}
function labelMeasure(m){return MNAME[m]||m}
function valueOf(c,m,s,y){var r=records.find(function(x){return x.cause===c&&x.measure===m&&x.sex===s&&x.year===y});return r?r.val:null}
function sumOf(m,s,y){return records.filter(function(x){return x.measure===m&&x.sex===s&&x.year===y}).reduce(function(a,x){return a+x.val},0)}
function unique(key){return Array.from(new Set(records.map(function(x){return x[key]})))}
function fingerprint(r){return [r.population_group,r.measure,r.location,r.sex,r.age,r.cause,r.rei,r.metric,r.year].join("||")}
function toast(message){var el=$("toast");el.textContent=message;el.classList.add("visible");clearTimeout(toastTimer);toastTimer=setTimeout(function(){el.classList.remove("visible")},3200)}
function parseCSV(text){
 text=String(text).replace(/^\uFEFF/,"");var rows=[],row=[],cell="",quoted=false;
 for(var i=0;i<text.length;i++){var ch=text[i];if(quoted){if(ch==='"'&&text[i+1]==='"'){cell+='"';i++}else if(ch==='"'){quoted=false}else{cell+=ch}}
 else if(ch==='"'){quoted=true}else if(ch===","){row.push(cell);cell=""}else if(ch==="\n"||ch==="\r"){if(ch==="\r"&&text[i+1]==="\n")i++;row.push(cell);if(row.some(function(x){return String(x).trim()!==""}))rows.push(row);row=[];cell=""}else{cell+=ch}}
 if(quoted)throw Error("CSV存在未闭合的引号");
 if(cell!==""||row.length){row.push(cell);rows.push(row)}
 if(rows.length<2)throw Error("CSV没有可用数据行");
 var cols=rows.shift().map(function(c){return c.trim()});
 var missing=HEADERS.filter(function(h){return cols.indexOf(h)<0});
 if(missing.length)throw Error("缺少必需列："+missing.join(", "));
 return rows.map(function(values,index){var record={id:"GBD-"+String(index+1).padStart(5,"0"),_index:index};
 cols.forEach(function(key,col){record[key]=(values[col]===undefined?"":values[col]).trim()});
 ["year","val","upper","lower"].forEach(function(key){record[key]=record[key]===""?NaN:Number(record[key])});
 record._key=fingerprint(record);return record});
}
function getView(){return records.filter(function(r){var term=$("recordSearch").value.trim().toLowerCase();
 var text=[r.id,r.cause,labelCause(r.cause),r.measure,labelMeasure(r.measure),r.sex,SEX[r.sex]||r.sex,r.year,r.location,r.rei].join(" ").toLowerCase();
 return (!term||text.indexOf(term)>=0)&&(!$("filterCause").value||r.cause===$("filterCause").value)&&(!$("filterMeasure").value||r.measure===$("filterMeasure").value)&&(!$("filterSex").value||r.sex===$("filterSex").value)&&(!$("filterYear").value||String(r.year)===$("filterYear").value)&&(!showFav||bookmarks.has(r._key))
 }).sort(function(a,b){var av=a[sortKey],bv=b[sortKey];if(typeof av==="number"||typeof bv==="number"){return ((Number(av)||0)-(Number(bv)||0))*sortDir}return String(av).localeCompare(String(bv),"zh")*sortDir})}
function fillSelect(id,values,labelFunc){var el=$(id),current=el.value;el.innerHTML=(el.querySelector('option[value=""]')?'<option value="">全部</option>':"");
 values.forEach(function(v){var opt=document.createElement("option");opt.value=v;opt.textContent=labelFunc?labelFunc(v):v;el.appendChild(opt)});
 if(values.indexOf(current)>=0)el.value=current}
function setData(data,sourceName){records=data;if(!records.length)throw Error("CSV没有数据记录");
 fillSelect("chartMeasure",unique("measure"),labelMeasure);
 fillSelect("compareMeasure",unique("measure"),labelMeasure);
 fillSelect("filterCause",unique("cause"),labelCause);
 fillSelect("filterMeasure",unique("measure"),labelMeasure);
 if(unique("measure").includes("DALYs (Disability-Adjusted Life Years)")){$("chartMeasure").value="DALYs (Disability-Adjusted Life Years)";$("compareMeasure").value="DALYs (Disability-Adjusted Life Years)"}
 $("sideCount").textContent=records.length;$("recordBadge").textContent=records.length+" 条源记录";
 $("fileInput").value="";curPage=1;renderAll();toast("已载入 "+records.length+" 条记录 · "+sourceName)}
function navigate(next){page=next;var names={dashboard:"数据总览",records:"数据档案",compare:"跨年比较",dictionary:"字段字典",quality:"质量核验"};
 document.querySelectorAll(".nav-item").forEach(function(el){el.classList.toggle("active",el.dataset.page===next)});
 document.querySelectorAll(".page").forEach(function(el){el.classList.toggle("active-page",el.id==="page-"+next)});
 $("breadcrumb").textContent=names[next];$("sidebar").classList.remove("mobile-open");$("exportBtn").hidden=(next!=="records"&&next!=="compare");window.scrollTo(0,0);
 if(next==="records")renderTable();if(next==="compare")renderCompare();
 if(next==="quality")renderQuality()}
function renderKpis(){var year=Number($("dashYear").value),sex=$("dashSex").value,comparison=year===2023?1990:2023;
 var classes=["","teal","amber","purple"],icons=["✚","◈","↗","≈"];
 $("kpiGrid").innerHTML=MEASURES.filter(function(m){return unique("measure").includes(m)}).map(function(m,i){var val=sumOf(m,sex,year),other=sumOf(m,sex,comparison),p=pct(other,val);
 return '<article class="kpi-card"><div class="kpi-top"><span class="kpi-tag">'+esc(labelMeasure(m))+' · '+year+'</span><span class="kpi-icon '+classes[i]+'">'+icons[i]+'</span></div><div class="kpi-value" title="'+fmt(val,5)+'">'+compact(val)+'</div><div class="kpi-bottom"><span class="kpi-name">三病种合计 · '+esc(SEX[sex]||sex)+'</span><span class="kpi-change '+(p!==null&&p<0?"negative":"")+'" title="与'+comparison+'年比较">'+(p===null?"—":(p>=0?"↑ ":"↓ ")+fmt(Math.abs(p),1)+"%")+'</span></div></article>'
 }).join("")}
function niceAxis(v){if(!v)return 1;var exp=Math.pow(10,Math.floor(Math.log10(v)));var steps=[1,2,2.5,5,10];return (steps.find(function(x){return x*exp>=v})||10)*exp}
function renderCauseChart(){var m=$("chartMeasure").value,sex=$("dashSex").value,causes=unique("cause"),w=690,h=260,left=67,right=15,top=18,bottom=56;
 var vals=[];causes.forEach(function(c){[1990,2023].forEach(function(y){vals.push(Math.max(0,valueOf(c,m,sex,y)||0))})});
 var ymax=niceAxis(Math.max.apply(null,vals)*1.12),plotW=w-left-right,plotH=h-top-bottom,group=plotW/Math.max(causes.length,1),barW=Math.min(46,group*.24);
 var svg='<svg viewBox="0 0 '+w+' '+h+'" role="img" aria-label="按疾病显示1990年和2023年'+esc(labelMeasure(m))+'的分组柱状图">';
 for(var k=0;k<=4;k++){var tick=ymax*k/4,y=top+plotH-plotH*k/4;svg+='<line x1="'+left+'" y1="'+y+'" x2="'+(w-right)+'" y2="'+y+'" stroke="#e9eff4" stroke-dasharray="'+(k===0?"0":"4 4")+'"/><text x="'+(left-12)+'" y="'+(y+4)+'" text-anchor="end" font-size="11">'+esc(shortNum(tick))+'</text>'}
 causes.forEach(function(c,i){var center=left+group*(i+.5);[1990,2023].forEach(function(year,j){var v=valueOf(c,m,sex,year)||0,barH=Math.max(0,v/ymax*plotH),x=center+(j===0?-barW-3:3);svg+='<rect x="'+x+'" y="'+(top+plotH-barH)+'" width="'+barW+'" height="'+barH+'" rx="4" fill="'+(j===0?"#c9e3ef":"#3077da")+'"><title>'+esc(labelCause(c))+' · '+year+' · '+fmt(v,2)+'</title></rect>'});
 var name=labelCause(c);svg+='<text x="'+center+'" y="'+(h-26)+'" font-size="11" font-weight="650" text-anchor="middle">'+esc(name)+'</text>'});
 svg+='</svg>';$("causeChart").innerHTML=svg;
}
function shortNum(n){return Math.abs(n)>=1000000?fmt(n/1000000,1)+"m":Math.abs(n)>=1000?fmt(n/1000,0)+"k":fmt(n,0)}
function renderDonut(){var m=$("chartMeasure").value,sex=$("dashSex").value,year=2023;
 var parts=unique("cause").map(function(c){return {c:c,val:Math.max(0,valueOf(c,m,sex,year)||0)}}),total=parts.reduce(function(a,b){return a+b.val},0),start=0,colors=[];
 parts.forEach(function(d,i){var finish=start+(total?d.val/total*100:0);colors.push(COLORS[i%COLORS.length]+" "+start+"% "+finish+"%");start=finish});
 $("donutChart").style.background=total?"conic-gradient("+colors.join(",")+")":"#e8eef4";$("donutTotal").textContent=compact(total);
 $("donutSubtitle").textContent=(SEX[sex]||sex)+" · "+labelMeasure(m)+" · 2023";
 $("donutLegend").innerHTML=parts.map(function(p,i){return '<div class="donut-item"><i style="background:'+COLORS[i%COLORS.length]+'"></i><div><span class="donut-label">'+esc(labelCause(p.c))+'</span><strong>'+(total?fmt(p.val/total*100,1):"0.0")+'%</strong></div></div>'}).join("");
}
function renderScope(){var list=[["疾病类型",unique("cause").length+" 种"],["记录条数",records.length+" 条"],["年份",unique("year").slice().sort().join(" / ")],["性别层级",unique("sex").length+" 类"],["负担指标",unique("measure").length+" 项"],["地区",unique("location").join(" / ")],["计量方式",unique("metric").join(" / ")],["危险因素",unique("rei").length+" 项"]];
 $("scopeGrid").innerHTML=list.map(function(x){return '<div class="scope-item"><span>'+esc(x[0])+'</span><strong title="'+esc(x[1])+'">'+esc(x[1])+'</strong></div>'}).join("")}
function renderDashboard(){renderKpis();renderCauseChart();renderDonut();renderScope()}
function renderTable(){var all=getView(),pageSize=Number($("pageSize").value),pages=Math.max(1,Math.ceil(all.length/pageSize));curPage=Math.min(Math.max(1,curPage),pages);var list=all.slice((curPage-1)*pageSize,curPage*pageSize);
 $("tableStatus").textContent="当前匹配 "+all.length+" / "+records.length+" 条记录";
 $("tableBody").innerHTML=list.length?list.map(function(r){return '<tr><td class="code-cell">'+esc(r.id)+'</td><td class="disease-cell">'+esc(labelCause(r.cause))+'</td><td>'+esc(labelMeasure(r.measure))+'</td><td><span class="sex-badge '+(r.sex==="Both"?"both":"")+'">'+esc(SEX[r.sex]||r.sex)+'</span></td><td><span class="year-badge '+(r.year===2023?"current":"")+'">'+esc(r.year)+'</span></td><td class="value-cell">'+fmt(r.val)+'</td><td class="ui-cell">'+fmt(r.lower)+' ~ '+fmt(r.upper)+'</td><td><button class="view-btn" data-detail="'+esc(r.id)+'">查看详情 →</button></td></tr>'}).join(""):'<tr><td colspan="8" class="empty-table">当前条件下没有符合要求的数据记录，请调整筛选条件。</td></tr>';
 $("pageInfo").textContent=all.length?"显示 "+((curPage-1)*pageSize+1)+"–"+Math.min(curPage*pageSize,all.length)+" 条，共 "+all.length+" 条":"无匹配记录";
 $("pageNumber").textContent=curPage+" / "+pages;$("prevPage").disabled=curPage===1;$("nextPage").disabled=curPage===pages;
 $("bookmarkBtn").textContent=showFav?"★ 正在查看收藏":"☆ 仅看收藏";$("bookmarkBtn").style.background=showFav?"#e8f6f1":"";
}
function pairRows(){var m=$("compareMeasure").value,s=$("compareSex").value;return unique("cause").map(function(c){var old=valueOf(c,m,s,1990),now=valueOf(c,m,s,2023);return {cause:c,old:old,now:now,delta:old===null||now===null?null:now-old,p:old===null||now===null?null:pct(old,now)}})}
function renderCompare(){var a=pairRows(),old=0,now=0,valid=0;a.forEach(function(r){if(r.old!==null&&r.now!==null){valid++;old+=r.old;now+=r.now}});
 var change=pct(old,now);
 $("compareOverview").innerHTML='<article class="compare-card"><small>1990 年 · 三病种合计</small><strong>'+compact(old)+'</strong><p>仅当前选择的单项指标与性别</p></article><article class="compare-card"><small>2023 年 · 三病种合计</small><strong>'+compact(now)+'</strong><p>已完整配对 '+valid+' / '+a.length+' 个病种</p></article><article class="compare-card"><small>1990—2023 相对变化</small><strong>'+ptext(change)+'</strong><p>变化率 = (2023 - 1990) / |1990| × 100%</p></article>';
 $("compareBody").innerHTML=a.map(function(r){return '<tr><td class="disease-cell">'+esc(labelCause(r.cause))+'</td><td class="value-cell">'+(r.old===null?"—":fmt(r.old))+'</td><td class="value-cell">'+(r.now===null?"—":fmt(r.now))+'</td><td>'+ (r.delta===null?"—":(r.delta>=0?"+":"")+fmt(r.delta))+'</td><td class="value-cell">'+ptext(r.p)+'</td><td><span class="status-badge '+(r.delta===null?"":r.delta>=0?"delta-up":"delta-down")+'">'+(r.delta===null?"缺少配对":r.delta>0?"↑ 上升":r.delta<0?"↓ 下降":"＝ 持平")+'</span></td></tr>'}).join("");
 var max=Math.max(1,...a.map(function(r){return Math.abs(r.p||0)}));
 $("changeBars").innerHTML=a.map(function(r){return '<div class="change-row"><span>'+esc(labelCause(r.cause))+'</span><div class="change-track"><div class="change-fill '+(r.p!==null&&r.p<0?"down":"")+'" style="width:'+(r.p===null?0:Math.abs(r.p)/max*100)+'%"></div></div><strong>'+ptext(r.p)+'</strong></div>'}).join("");
}
var DICT=[
 ["population_group","人群分组","文本","当前文件为 All Population"],
 ["measure","疾病负担指标","文本","Deaths / DALYs / YLLs / YLDs"],
 ["location","地理位置","文本","China"],
 ["sex","性别","文本","Both / Male / Female"],
 ["age","年龄组","文本","All ages（全年龄）"],
 ["cause","疾病或病因","文本","2型糖尿病、缺血性卒中、缺血性心脏病"],
 ["rei","可归因风险因素","文本","Low physical activity（低体力活动）"],
 ["metric","数值量纲","文本","Number（绝对数量，非率）"],
 ["year","年份","整数","1990 或 2023"],
 ["val","估计值","数值","GBD 原始估计，不改变其精度"],
 ["upper","不确定区间上限","数值","原始 95% UI 上限"],
 ["lower","不确定区间下限","数值","原始 95% UI 下限，可能小于 0"]
];
function renderDictionary(){$("dictionaryBody").innerHTML=DICT.map(function(d){return '<tr><td><code>'+esc(d[0])+'</code></td><td class="disease-cell">'+esc(d[1])+'</td><td>'+esc(d[2])+'</td><td>'+esc(d[3])+'</td></tr>'}).join("")}
function renderQuality(){var missing=0,invalid=0,negative=0,identical=new Set(),duplicates=0;
 records.forEach(function(r){HEADERS.forEach(function(key){if(r[key]===undefined||r[key]===null||r[key]===""||typeof r[key]==="number"&&!Number.isFinite(r[key]))missing++});
 if(Number.isFinite(r.val)&&Number.isFinite(r.upper)&&Number.isFinite(r.lower)&&(r.val<r.lower||r.val>r.upper||r.lower>r.upper))invalid++;
 if(Number.isFinite(r.lower)&&r.lower<0)negative++;
 if(identical.has(r._key))duplicates++;else identical.add(r._key)});
 var combinations=unique("cause").length*unique("measure").length*unique("sex").length*unique("year").length;
 var checks=[
 ["空缺单元格","12个原始字段逐行检查，空值和无法解析的数字均计入",missing,missing?"需检查":"通过"],
 ["维度组合重复","按人群、指标、地区、性别、年龄、病种、风险因素、量纲及年份建立复合键",duplicates,duplicates?"需检查":"通过"],
 ["估计值越界","检查 lower ≤ val ≤ upper 及 lower ≤ upper",invalid,invalid?"需检查":"通过"],
 ["不确定区间下限为负","仅提示来源估计存在负下限，不对原始数值进行截断",negative,negative?"注意":"通过"],
 ["维度组合覆盖","当前文件中出现的疾病 × 指标 × 性别 × 年份组合："+identical.size+" / "+combinations,Math.max(0,combinations-identical.size),combinations===identical.size?"完整":"非完全交叉"]
 ];
 $("qualityGrid").innerHTML=[["总记录数",records.length,"CSV 数据行"],["缺失单元格",missing,"共12个必需字段"],["重复维度组合",duplicates,"按复合主键核验"],["负下限记录",negative,"保留原始估计"]].map(function(x){return '<div class="quality-stat"><small>'+x[0]+'</small><strong>'+x[1]+'</strong><span>'+x[2]+'</span></div>'}).join("");
 $("qualityChecks").innerHTML=checks.map(function(c){return '<div class="quality-check '+(c[2]?"warn":"")+'"><span class="check-icon">'+(c[2]?"!":"✓")+'</span><div><strong>'+esc(c[0])+'</strong><p>'+esc(c[1])+'</p></div><span class="check-status">'+esc(c[3])+(c[2]?" · "+c[2]+"条":"")+'</span></div>'}).join("");
}
function renderAll(){renderDashboard();renderTable();renderCompare();renderDictionary();renderQuality()}
function openDetail(id){var r=records.find(function(x){return x.id===id});if(!r)return;selected=r;
 var fields=HEADERS.map(function(key){return '<div class="detail-field"><span>'+esc(key)+'</span><strong>'+esc(r[key])+'</strong></div>'}).join("");
 var other=valueOf(r.cause,r.measure,r.sex,r.year===2023?1990:2023),change=other===null?null:pct(other,r.val);
 $("drawerBody").innerHTML='<div class="detail-id">'+esc(r.id)+'</div><h3 class="detail-title">'+esc(labelCause(r.cause))+'</h3><p class="detail-sub">'+esc(labelMeasure(r.measure))+' · '+esc(SEX[r.sex]||r.sex)+' · '+esc(r.year)+'年 · '+esc(r.location)+'</p><div class="detail-value-card"><small>原始估计值（'+esc(r.metric)+'）</small><strong>'+fmt(r.val,4)+'</strong><div class="detail-range">95% UI：'+fmt(r.lower,4)+' ~ '+fmt(r.upper,4)+'</div></div><div class="detail-field-heading">原始CSV字段 · 共 12 项</div>'+fields+'<p class="detail-note">对应另一年份估计值：'+(other===null?"未收录":fmt(other,2))+'。相对另一年份变化：'+ptext(change)+'。数值不经过修正或插值；收藏状态仅保存于本机浏览器。</p>';
 $("drawerBookmarkBtn").textContent=bookmarks.has(r._key)?"★ 取消收藏":"☆ 收藏记录";$("detailsDrawer").classList.add("open");$("detailsDrawer").setAttribute("aria-hidden","false");$("scrim").hidden=false}
function closeDetail(){$("detailsDrawer").classList.remove("open");$("detailsDrawer").setAttribute("aria-hidden","true");$("scrim").hidden=true;selected=null}
function toCSV(rows,headers){function quote(v){var s=String(v===undefined||v===null?"":v);return /[",\r\n]/.test(s)?'"'+s.replace(/"/g,'""')+'"':s}
 return [headers.join(",")].concat(rows.map(function(r){return headers.map(function(h){return quote(r[h])}).join(",")})).join("\r\n")}
function download(name,text){var blob=new Blob(["\uFEFF",text],{type:"text/csv;charset=utf-8"}),url=URL.createObjectURL(blob),a=document.createElement("a");a.href=url;a.download=name;document.body.appendChild(a);a.click();a.remove();setTimeout(function(){URL.revokeObjectURL(url)},1000);toast("CSV 已导出："+name)}
function exportCurrent(){if(page==="compare"){exportCompare();return}if(page!=="records")return;download("GBD_2023_filtered.csv",toCSV(getView(),HEADERS))}
function exportCompare(){var rows=pairRows().map(function(x){return {cause:x.cause,measure:$("compareMeasure").value,sex:$("compareSex").value,val_1990:x.old,val_2023:x.now,absolute_change:x.delta,percentage_change:x.p}});download("GBD_1990_2023_comparison.csv",toCSV(rows,["cause","measure","sex","val_1990","val_2023","absolute_change","percentage_change"]))}
function resetFilters(){$("recordSearch").value="";["filterCause","filterMeasure","filterSex","filterYear"].forEach(function(id){$(id).value=""});showFav=false;curPage=1;renderTable()}
function handlers(){
 document.querySelectorAll(".nav-item").forEach(function(el){el.addEventListener("click",function(){navigate(el.dataset.page)})});
 $("dashYear").addEventListener("change",renderDashboard);$("dashSex").addEventListener("change",renderDashboard);
 $("chartMeasure").addEventListener("change",function(){renderCauseChart();renderDonut()});
 ["recordSearch","filterCause","filterMeasure","filterSex","filterYear"].forEach(function(id){$(id).addEventListener(id==="recordSearch"?"input":"change",function(){curPage=1;renderTable()})});
 $("bookmarkBtn").addEventListener("click",function(){showFav=!showFav;curPage=1;renderTable()});
 $("resetBtn").addEventListener("click",resetFilters);
 $("pageSize").addEventListener("change",function(){curPage=1;renderTable()});
 $("prevPage").addEventListener("click",function(){curPage--;renderTable()});$("nextPage").addEventListener("click",function(){curPage++;renderTable()});
 document.querySelectorAll("th[data-sort]").forEach(function(el){el.addEventListener("click",function(){if(sortKey===el.dataset.sort)sortDir*=-1;else{sortKey=el.dataset.sort;sortDir=sortKey==="val"||sortKey==="year"?-1:1}curPage=1;renderTable()})});
 $("tableBody").addEventListener("click",function(e){var btn=e.target.closest("[data-detail]");if(btn)openDetail(btn.dataset.detail)});
 ["compareMeasure","compareSex"].forEach(function(id){$(id).addEventListener("change",renderCompare)});
 $("exportBtn").addEventListener("click",exportCurrent);$("compareExportBtn").addEventListener("click",exportCompare);
 $("drawerClose").addEventListener("click",closeDetail);$("scrim").addEventListener("click",closeDetail);document.addEventListener("keydown",function(e){if(e.key==="Escape")closeDetail()});
 $("drawerBookmarkBtn").addEventListener("click",function(){if(!selected)return;var key=selected._key;if(bookmarks.has(key))bookmarks.delete(key);else bookmarks.add(key);saveBookmarks();$("drawerBookmarkBtn").textContent=bookmarks.has(key)?"★ 取消收藏":"☆ 收藏记录";renderTable();toast(bookmarks.has(key)?"已收藏本条记录":"已取消收藏")});
 $("copyRecordBtn").addEventListener("click",function(){if(!selected)return;var obj={};HEADERS.forEach(function(k){obj[k]=selected[k]});var text=JSON.stringify(obj,null,2);if(navigator.clipboard&&navigator.clipboard.writeText){navigator.clipboard.writeText(text).then(function(){toast("已复制原始记录 JSON")}).catch(function(){toast("复制失败，请检查浏览器权限")})}else{toast("当前浏览器不支持剪贴板复制")}});
 $("importBtn").addEventListener("click",function(){$("fileInput").click()});$("fileInput").addEventListener("change",async function(e){var file=e.target.files[0];if(!file)return;try{var text=await file.text();setData(parseCSV(text),file.name);navigate("records")}catch(error){toast("导入失败："+error.message)}});
 $("menuBtn").addEventListener("click",function(){$("sidebar").classList.toggle("mobile-open")});
}
async function init(){handlers();try{var response=await fetch(SOURCE,{cache:"no-cache"});if(!response.ok)throw Error("HTTP "+response.status);var text=await response.text();setData(parseCSV(text),"原始 GBD 2023 CSV")}catch(error){$("kpiGrid").innerHTML='<div class="loading">数据载入失败：'+esc(error.message)+'。请通过本地 HTTP 服务或 GitHub Pages 打开网页，或点击右上方「导入CSV」加载数据。</div>';toast("数据载入失败，请检查静态文件路径")}}
init();
})();