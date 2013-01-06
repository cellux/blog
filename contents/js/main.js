$(function() {
    if ($(".gallery").length) {
        Galleria.loadTheme('/js/galleria.classic.min.js');
        Galleria.configure({
            imageCrop: 'width',
        });
        $(".gallery").each(function(i,e) {
            Galleria.run('#'+e.id);
        });
    }
    $("#nav img").hover(function() {
        $(this).animate({
            top: "-=4",
            left: "-=4",
            height: "+=8",
        }, 100, 'swing');
    }, function() {
        $(this).animate({
            top: "+=4",
            left: "+=4",
            height: "-=8",
        }, 100, 'swing');
    });
});
