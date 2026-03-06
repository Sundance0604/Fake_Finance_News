
* 切换到数据所在路径(根据自己路径修改)
cd D:\事件研究\


* 结果输出路径
global res_path D:\事件研究\输出

*==========================================================
*                     基础数据整理
*==========================================================


*= 导入日个股回报率数据
* 数据分别命名成 TRD_Dalyr1  TRD_Dalyr2 TRD_Dalyr3 ....
forvalues i=1/3 {
	import delimited TRD_Dalyr`i'.csv, encoding(utf-8) clear
	save 日个股回报率`i'.dta, replace
}

* 合并数据
* 使用append 纵向合并
clear
forvalues i=1/3 {
   append using 日个股回报率`i'.dta
}
* 重命名变量
rename trddt 交易日期
rename dretwd 个股回报率
save 日个股回报率.dta, replace

*= 导入市场回报率数据
import excel 综合日市场回报率.xlsx, firstrow clear

* 综合市场类型 - 5=综合A股市场， 10=综合B股市场， 15=综合AB股市场， 21=综合A股和创业板； 31=综合AB股和创业； 37=综合A股和科创板； 47=综合AB股和科创板； 53=综合A股和创业板和科创板； 63=综合AB股和创业板和科创板。
keep if 综合市场类型==117

* 重命名变量
rename 考虑现金红利再投资的综合日市场回报率流通市值加权平均法 市场回报率
save 市场回报率.dta, replace

*= 合并日个股回报率和市场回报率
use 日个股回报率.dta, clear

* 使用m:1多对一匹配
* nogen就是不生成 _merge 变量
* keep(1 3) 就是等同于 keep if _merge==1 | _merge==3
* keepusing() 里面放入想要匹配进去的变量，默认是全部变量
merge m:1 交易日期 using 市场回报率.dta, nogen keep(1 3) keepusing(市场回报率)
save 收益率数据.dta, replace

*==========================================================
*                     计算异常收益率
*==========================================================


* 合并数据
use 事件日.dta, clear
*源文件是事件日期
gen stkcd=real(证券代码)
joinby stkcd using 收益率数据.dta 

*= 收益率用百分比
replace 个股回报率=个股回报率*100
replace 市场回报率=市场回报率*100


*= 交易日期转化连续数字
* 因为存在周末和假日，交易日期是不连续的
sort 证券代码 事件日期 交易日期 
by 证券代码 事件日期: gen date_num=_n


* 将字符格式变化日期格式 
gen trade_date=date(交易日期,"YMD") 
format trade_date %td
gen event_date=date(事件日期,"YMD") 
format event_date %td

* 部分公司事件公告日不是在交易日 以往后推最近的一个交易日
gen 间隔时间=trade_date-event_date
* 事件日期之前的不包含在内
replace 间隔时间=. if 间隔时间<0  
egen min_dif = min(间隔时间),  by(证券代码 event_date)

gen target=date_num if 间隔时间==min_dif
egen td=mean(target), by(证券代码 event_date)

drop 间隔时间 min_dif target

* 计算和事件日期间隔多少个交易日
gen dif=date_num-td


*更改区间和区间间隔天数


* 事件窗口期[-10, +10]
bys 证券代码 event_date: gen event_window=1 if dif>=-10 & dif<=10

* 估计窗口期[-110, -11]
bys 证券代码 event_date: gen estimation_window=1 if dif>=-70 & dif<=-11
replace event_window=0 if event_window==.
replace estimation_window=0 if estimation_window==.
drop if event_window==0 & estimation_window==0

* 剔除估计窗口期不足的（区间变了，注意修改数值，示例中估计窗口期[-110, -11]总共100天）
bys 证券代码 event_date: egen estimation_num=sum(estimation_window)
drop if estimation_num<60

egen id=group(证券代码 事件日期)
gen predicted_return=.

* 获取总共有多少个事件MaxID  
* global 定义的是全局
sum id
global MaxID=r(max)


* 计算估计收益率 (循环回归 运行时间可能会久一些)
forvalues i=1(1)$MaxID {
	qui reg 个股回报率 市场回报率 if id==`i' & estimation_window==1 
	predict temp if id==`i' 
	replace predicted_return=temp if id==`i' & event_window==1
	drop temp
}


* 异常收益率AR
keep if event_window==1
gen AR=个股回报率-predicted_return 

* 计算累计异常收益率CAR
sort id dif
by id: gen CAR=sum(AR)
save data.dta, replace

*==========================================================
*                      走势图
*==========================================================

* 走势图
use data.dta, clear
collapse (mean) AAR=AR CAAR=CAR, by(dif)
label var AAR "AAR"
label var CAAR "CAAR"
twoway (line AAR dif, lcolor(orange_red ) lpattern(solid) ) (line CAAR dif, lcolor(blue ) lpattern(longdash)), ylabel(, format(%7.2f)) xlabel(-10(2)10)
graph export $res_path/走势图.png, replace



*==========================================================
*                     AR显著性检验 
*==========================================================

* 计算AR显著性检验
use data.dta, clear

* 使用collapse 聚合计算  (mean) 计算均值  (sd)计算标准差
collapse (mean) AAR=AR (sd) sd=AR (count) n=AR, by(dif)

* 计算t统计量
gen t值=AAR/(sd/sqrt(n))

* 计算t统计量对应的p值
gen p值=ttail(n, abs(t))*2

* 标注星星 ***、**、*分别表示在1%、5%、10%的水平上显著
gen star="***" if p<0.01
replace star="**" if p<0.05 & star==""
replace star="*" if p<0.1 & star==""

drop sd n 
format AAR t p %7.4f
save $res_path/AR显著性检验.dta, replace





*==========================================================
*                 不同区间的CAR显著性检验 
*==========================================================

* 不同区间的累计平均异常收益率 
use data.dta, clear
sort id dif

* 计算不同区间的累计平均异常收益率，根据自己的需求设置，我设置的比较多
by id: egen CAR_1= sum(AR) if dif>=-10 & dif<=10
by id: egen CAR_2= sum(AR) if dif>=-5 & dif<=5
by id: egen CAR_3= sum(AR) if dif>=-4 & dif<=4
by id: egen CAR_4= sum(AR) if dif>=-3 & dif<=3
by id: egen CAR_5= sum(AR) if dif>=-2 & dif<=2
by id: egen CAR_6= sum(AR) if dif>=-1 & dif<=1
by id: egen CAR_7= sum(AR) if dif==0
by id: egen CAR_8= sum(AR) if dif>=-10 & dif<=0
by id: egen CAR_9= sum(AR) if dif>=-5 & dif<=0
by id: egen CAR_10= sum(AR) if dif>=-4 & dif<=0
by id: egen CAR_11= sum(AR) if dif>=-3 & dif<=0
by id: egen CAR_12= sum(AR) if dif>=-2 & dif<=0
by id: egen CAR_13= sum(AR) if dif>=-1 & dif<=0
by id: egen CAR_14= sum(AR) if dif>=0 & dif<=1
by id: egen CAR_15= sum(AR) if dif>=0 & dif<=2
by id: egen CAR_16= sum(AR) if dif>=0 & dif<=3
by id: egen CAR_17= sum(AR) if dif>=0 & dif<=4
by id: egen CAR_18= sum(AR) if dif>=0 & dif<=5
by id: egen CAR_19= sum(AR) if dif>=0 & dif<=10



collapse (mean) CAR_1 CAR_2 CAR_3 CAR_4 CAR_5 CAR_6 CAR_7 CAR_8 CAR_9 CAR_10 CAR_11 CAR_12 CAR_13 CAR_14 CAR_15 CAR_16 CAR_17 CAR_18 CAR_19, by(id)
* 显著性检验
forv i=1/19 {

  * 求均值
  egen CAAR_`i'=mean(CAR_`i')
  
  * 求标准差
  egen sd_`i'=sd(CAR_`i')
  
  * 计算t统计量
  gen t_`i'=CAAR_`i'/(sd_`i'/sqrt(_N))
  
  * 计算p值
  gen p_`i'=ttail(_N, abs(t_`i'))*2
}


keep CAAR_* t_* p_* 
keep if _n==1

* 数据转换方向，调整格式
gen i=1
reshape long CAAR_ t_ p_,i(i) j(j)

* 区间命名, 和上面设置的区间对应
gen 区间="[-10, 10]" if j==1
replace 区间="[-5, 5]" if j==2
replace 区间="[-4, 4]" if j==3
replace 区间="[-3, 3]" if j==4
replace 区间="[-2, 2]" if j==5
replace 区间="[-1, 1]" if j==6
replace 区间="[0]" if j==7
replace 区间="[-10, 0]" if j==8
replace 区间="[-5, 0]" if j==9
replace 区间="[-4, 0]" if j==10
replace 区间="[-3, 0]" if j==11
replace 区间="[-2, 0]" if j==12
replace 区间="[-1, 0]" if j==13
replace 区间="[0, 1]" if j==14
replace 区间="[0, 2]" if j==15
replace 区间="[0, 3]" if j==16
replace 区间="[0, 4]" if j==17
replace 区间="[0, 5]" if j==18
replace 区间="[0, 10]" if j==19


order 区间 CAAR t p
drop i j

* 显著性标注 *、**、***分别表示在10%、5%、1%的水平上显著
gen star="***" if p<0.01
replace star="**" if p<0.05 & star==""
replace star="*" if p<0.1 & star==""

* 变量重命名
rename CAAR_ CAAR
rename t_ t
rename p_ p

format CAAR t p %7.4f
save $res_path/CAR显著性检验.dta, replace


