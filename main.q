
.var.homedir:getenv[`HOME],"/git/segment_comparison";
.var.accessToken:@[{first read0 x};hsym `$.var.homedir,"/settings/token.txt";{"null token"}];
.var.commandBase:"curl -G https://www.strava.com/api/v3/";
.var.dateRange.activities:();
.var.athleteData:();

system"l ",.var.homedir,"/settings/sampleIds.q";

.log.out:{-1 string[.z.p]," | Info | ",x;};
.log.error:{-1 string[.z.p]," | Error | ",x; 'x};

.cache.leaderboards:@[value;`.cache.leaderboards;([segmentId:`long$(); resType:`$(); resId:`long$()] res:())];
.cache.activities:@[value;`.cache.activities;([id:`long$()] name:(); start_date:`date$(); manual:`boolean$(); commute:`boolean$())];
.cache.segments:@[value;`.cache.segments;([id:`long$()] name:(); starred:`boolean$())];
.cache.clubs:@[value;`.cache.clubs;([id:`long$()] name:())];
.cache.athletes:@[value;`.cache.athletes;([id:`long$()] name:())];

.var.defaults:flip `vr`vl`fc!flip (
  (`starred      ; 0b   ; ("false";"true")                                        );  / show starred segments
  (`following    ; 0b   ; ("false";"true")                                        );  / compare with those followed
  (`include_clubs; 0b   ; ("false";"true")                                        );  / for club comparison
  (`after        ; 0Nd  ; {string (-/)`long$(`timestamp$x;1970.01.01D00:00)%1e9}  );  / start date
  (`before       ; 0Nd  ; {string (-/)`long$(`timestamp$1+x;1970.01.01D00:00)%1e9});  / end date
  (`club_id      ; (),0N; string                                                  );  / for club comparison
  (`segment_id   ; 0N   ; string                                                  );  / segment to compare on
  (`page         ; 0N   ; string                                                  );  / number of pages
  (`per_page     ; 0N   ; string                                                  )   / results per page
 );

/ basic connect function
.connect.simple:{[datatype;extra]
  :-29!first system .var.commandBase,datatype," -d access_token=",.var.accessToken," ",extra;       / return dictionary attribute-value pairs
 };

.connect.pagination:{[datatype;extra]
  :last {[datatype;extra;tab]                   / iterate over pages until no extra results are returned
    tab[1],:ret:.connect.simple[datatype;extra," -d page=",string tab 0];
    if[count ret; tab[0]+:1];
    :tab;
  }[datatype;extra]/[(1;())];
 };

/ show results neatly
showRes:{[segId;resType;resId]
  :([] segmentId:enlist segId) cross .cache.leaderboards[(segId;resType;resId)]`res;
 };

.segComp.base:{[dict]
  empty:([] Segment:`long$(); athlete_id:`long$(); athlete_name:`$(); elapsed_time:`minute$());
  if[not max dict`following`include_clubs; :empty];
  bb:0!.return.segments[dict];
  details:$[(7=type dict`club_id)&(not all null dict`club_id);
    flip[dict] cross ([] segment_id:bb`id);
    {x[`segment_id]:y; x}[dict]'[bb`id]];
  cc:.return.leaderboard.all each details;
  res:@[raze cc where 1<count each cc;`athlete_name;`$];
  `.cache.athletes upsert distinct select id:athlete_id, name:athlete_name from res;
  :res;
 };

/ compare segments
.segComp.leaderboard:{[dict]
  dd:.segComp.base[dict];
  empty:![([] Segment:());();0b;enlist[(`$string `long$.return.athleteData[][`id])]!()];
  if[0=count dd; :empty];
  P:asc exec distinct `$string athlete_id from dd;
  res:0!exec P#((`$string athlete_id)!elapsed_time) by Segment:Segment from dd;
  cl:`Segment,`$string`long$.return.athleteData[][`id];
  :(cl,cols[res] except cl) xcols res;
 };

.segComp.hr.leaderboard:{[dict]
  res:.segComp.leaderboard dict;
  ath:.return.athleteName each "J"$string 1_ cols res;
  :(`Segment,ath) xcol update .return.segmentName each Segment from res;
 };

.segComp.html.leaderboard:{[dict]
  res:.segComp.leaderboard dict;
//  ath:`$.return.html.athleteURL each "J"$string 1_ cols res;
//  res:(`Segment,ath) xcol res;
  ath:.return.athleteName each "J"$string 1_ cols res;
  :(`Segment,ath) xcol update .return.html.segmentURL each Segment from res;
 };

.segComp.highlight:{[dict]
  dd:.segComp.base[dict];
  ee:select Segment, athlete_name, elapsed_time, minTime:(min;elapsed_time) fby Segment from dd;
  ff:update elapsed_time:{$[x=y;"<mark>",string[x],"</mark>";string x]}'[elapsed_time;minTime] from ee;
  P:asc exec distinct athlete_name from ff;
  res:0!exec P#(athlete_name!elapsed_time) by Segment:Segment from ff;
  cl:`Segment,.return.athleteData[][`fullname];
  :(cl,cols[res] except cl) xcols res;
  }

.segComp.summary:{[dict]
  dd:.segComp.base[dict];
  ee:select Segment, athlete_name, elapsed_time, minTime:(min;elapsed_time) fby Segment from dd;
  :`total xdesc select total:count[Segment], Segment by athlete_name from ee where elapsed_time=minTime, 1=(count;i) fby Segment; 
 };

/ return dictionary of date status
.return.datelist.check:{[t;s;e]                                   / [type;start;end]
  v:sv[`;`.var.dateRange,t];
  if[14<>type s,e; :.log.error"Need to provide a date range"];
  dr:asc distinct (s,e),s+til 1^(e+1)-s;
  d:(!/)flip dr,'0b;
  d[value v]:1b;
  :d;
 };

/ return existing parameters in correct format
.return.clean:{[dict]
  def:(!/) .var.defaults`vr`vl;                             / defaults value for parameters
  :.Q.def[def] string key[def]!(def,dict) key[def];         / return valid optional parameters
 };

/ build url from specified altered parameters
.return.params.all:{[params;dict]
  if[0=count dict; :""];                                    / if no parametrs return empty string
  def:(!/) .var.defaults`vr`vl;                             / defaults value for parameters
  n:inter[(),params] where not def~'.Q.def[def] {$[10=abs type x;x;string x]} each dict; / return altered parameters
  :" " sv ("-d ",/:string[n],'"="),'{func:exec fc from .var.defaults where vr in x; raze func @\: y}'[n;dict n];  / return parameters
 };

.return.params.valid:{[params;dict] .return.params.all[params] .return.clean[dict]}

/ return activities
.return.activities:{[dict]
  dr:.return.datelist[`check][`activities;dict`after;dict`before];
  if[0=count where not dr; :select from .cache.activities where start_date in where dr];  / return cached results if they exist
  p:.return.params.valid[`before`after`per_page;dict];     / additional url parameters
  activ:.connect.pagination["activities";p];           / connect and return activites
  rs:{select `long$id, name, "D"$10#\:start_date, manual, commute from x} each activ;  / extract relevent fields
  `.cache.activities upsert rs;
  `.var.dateRange.activities set asc distinct .var.dateRange.activities,where not dr;
  :`id xkey rs;
 };

/ return segment data from activity list
.return.segments:{[dict]
  if[count cr:select from .cache.segments; :cr];            / if results cached then return here
  activ:.return.activities[dict];
  if[0=count activ; :cr];
  segs:.connect.simple[;""] each "activities/",/:string exec id from activ where not manual;
  rs:distinct select `long$id, name, starred from raze[segs`segment_efforts]`segment where not private, not hazardous;  / return segment ids from activities
  rs,:select `long$id, name, starred from .connect.simple["segments/starred";""];  / return starred segments
  `.cache.segments upsert rs;                               / upsert to segment cache
  :`id xkey rs;
 };

.return.segmentName:{[id]
  if[count segName:.cache.segments[id]`name; :segName];     / if cached then return name
//  .log.out"Retrieving segments";
  res:.connect.simple ["segments/",string id;""]`name;      / else request data
//  .log.out"Returning segments";
  :res;
 };

.return.html.segmentURL:{[id]
  name:.return.segmentName[id];
  .h.ha["http://www.strava.com/segments/",string id;name]
 };

.return.athleteName:{[id] first value .cache.athletes id};

.return.html.athleteURL:{[id]      / for use with .cache.leaderboards
  name:.return.athleteName[id];
  .h.ha["http://www.strava.com/athletes/",string id;string name]
 };

/ return list of users clubs
.return.clubs:{[]
  .return.athleteData[];
  if[count .cache.clubs; :.cache.clubs];
  `.cache.clubs upsert rs:select `long$id, name from .return.athleteData[][`clubs];
  :`id xkey rs;
 };

.return.athleteData:{[]
  if[0<count .var.athleteData; :.var.athleteData];
  ad:.connect.simple["athlete";""];
  ad[`fullname]:`$" " sv ad[`firstname`lastname];
  `.var.athleteData set ad;
  :ad;
 };

.return.leaderboard.all:{[dict]
  if[not `segment_id in key dict; .log.error"Need to specify a segment id"; :()];
  rs:([athlete_id:`long$()] athlete_name:(); elapsed_time:`minute$(); Segment:`long$());
  if[1b=dict`following; rs,:.return.leaderboard.following[dict]];       / return leaderboard of followers
  if[not any null dict`club_id; rs,:.return.leaderboard.club[dict]];    / return leaderboard of clubs
  :`Segment xcols 0!rs;
 };

.return.leaderboard.club:{[dict]
  if[0<count rs:.cache.leaderboards[(dict`segment_id;`club;dict`club_id)]`res;
    :rs cross ([] Segment:enlist dict`segment_id);
  ];
  extra:.return.params.valid[`club_id] dict;
  message:.connect.simple["segments/",string[dict`segment_id],"/leaderboard"] extra;
  clb:select `long$athlete_id, athlete_name, `minute$elapsed_time from message`entries;
  `.cache.leaderboards upsert (dict`segment_id;`club;dict`club_id;clb);
  :clb cross ([] Segment:enlist dict`segment_id);
 };

.return.leaderboard.following:{[dict]
  if[0<count rs:.cache.leaderboards[(dict`segment_id;`following;0N)]`res;
    :rs cross ([] Segment:enlist dict`segment_id);
  ];
  extra:.return.params.valid[`following] dict;
  message:.connect.simple["segments/",string[dict`segment_id],"/leaderboard"] extra;
  fol:select `long$athlete_id, athlete_name, `minute$elapsed_time from message`entries;
  `.cache.leaderboards upsert (dict`segment_id;`following;0N;fol);
  :fol cross ([] Segment:enlist dict`segment_id);
 };
