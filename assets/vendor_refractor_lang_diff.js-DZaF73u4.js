var n,d;function u(){if(d)return n;d=1,n=i,i.displayName="diff",i.aliases=[];function i(t){(function(f){f.languages.diff={coord:[/^(?:\*{3}|-{3}|\+{3}).*$/m,/^@@.*@@$/m,/^\d.*$/m]};var r={"deleted-sign":"-","deleted-arrow":"<","inserted-sign":"+","inserted-arrow":">",unchanged:" ",diff:"!"};Object.keys(r).forEach(function(e){var s=r[e],a=[];/^\w+$/.test(e)||a.push(/\w+/.exec(e)[0]),e==="diff"&&a.push("bold"),f.languages.diff[e]={pattern:RegExp("^(?:["+s+`].*(?:\r
?|
|(?![\\s\\S])))+`,"m"),alias:a,inside:{line:{pattern:/(.)(?=[\s\S]).*(?:\r\n?|\n)?/,lookbehind:!0},prefix:{pattern:/[\s\S]/,alias:/\w+/.exec(e)[0]}}}}),Object.defineProperty(f.languages.diff,"PREFIXES",{value:r})})(t)}return n}export{u as r};
//# sourceMappingURL=vendor_refractor_lang_diff.js-DZaF73u4.js.map
