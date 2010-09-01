global_catchkeys = 1;
function read(id){
  var el = $('#details'+id).get(0);
  if (el.style.display == 'none') 
  {
    // Open us up for reading!
    $('#entry'+id).addClass('open_for_reading');
    el.style.display = 'block';
    window.location='#anchor'+id;
    /* Also, mark read */
    $.ajax({
      url: "/read/"+id,
      type: "GET",
      success: function(msg) {
        // Mark as read.
        $('#entry'+id).addClass('read');
      },
      error: function(req, status, error) {
      //alert('Error: '+status+error);
      },
    });
  } 
  else 
  {
    $('#entry'+id).removeClass('open_for_reading');
    el.style.display = 'none';
  }
}

function toggle_star(id)
{
  if($("#star"+id).attr("src").match(/darkstar/))
  {
    // Star it!
    $.get("/star/"+id, function(data) {
      $("#star"+id).attr("src", "star.png");
    });
  }
  else
  {
    // Unstar it!
    $.get("/unstar/"+id, function(data) {
      $("#star"+id).attr("src", "darkstar.png");
    });
  }
}

function clear_read()
{
  $.get("/clear", 
    function(data) {
      $(".read").each(function(idx) {
        $(this).remove();
      })
    });
}

$(document).ready(function() {
  // Set up dropdowns
  $('#num').change(function(){  
    window.location.href = "/?num="+$('#num').get(0).value;
  });

  // Bind submit function for add
  $('#newfeed').submit(function() {
    $.post("add", {'url': $('#url').get(0).value},
      function(data) {
        alert("Successfully added the url.");
        $('#url').get(0).value = "";
      }
    );
  });

});

// Implement keypresses
$(document).keypress(function(ev)
{
    if(!global_catchkeys) return true;
    //alert("Pressed "+ev.keyCode);
    if(ev.which === 106) 
    { // J
      var el = $('.open_for_reading');
      var reg = /entry([0-9]+)/;
      if(el.size() == 0)
      {
        // Nothing's open.  Just open the first entry
        el = $('.entry:first');
        var kalel = el.get(0);
        if(kalel == undefined) return false;
        var matcharray = reg.exec(kalel.id);
        var open_id = matcharray[1];
        read(open_id);
      }
      else
      {
        var kalel = el.get(0);
        if(kalel == undefined) return false;
        var matcharray = reg.exec(kalel.id);
        var close_id = matcharray[1];
        matcharray = reg.exec(el.nextAll("div").get(0).id);
        var open_id = matcharray[1];
        if(open_id == null) return;
        read(close_id);
        read(open_id);
      }
    }
    else if(ev.which === 107)
    { // K
      var el = $('.open_for_reading');
      if(el != null)
      {
        var reg = /entry([0-9]+)/;
        var kalel = el.get(0);
        if(kalel == undefined) return false;
        var matcharray = reg.exec(kalel.id);
        var close_id = matcharray[1];
        matcharray = reg.exec(el.prevAll("div").get(0).id);
        var open_id = matcharray[1];
        if(open_id == null) return;
        read(close_id);
        read(open_id);
      }
    }
    else if(ev.which === 111)
    { //O
      // Open for reading elsewhere!
      var el = $('.open_for_reading');
      window.open(el.find("a.orig_link").attr("href"), "_blank");
    }
    else if(ev.which === 115)
    { // S
      var el = $('.open_for_reading');
      if(el != null)
      {
        var reg = /entry([0-9]+)/;
        var matcharray = reg.exec(el.get(0).id);
        var id = matcharray[1];
        if(id == null) return;
        toggle_star(id);
      }
    }
    else {
      alert(ev.which);
    }
});
