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
});

// Implement keypresses
$(document).keypress(function(ev)
{
    //alert("Pressed "+ev.keyCode);
    if(ev.keyCode == 106) 
    { // J
      var el = $('.open_for_reading');
      if(el.size() == 0)
      {
        // Nothing's open.  Just open the first entry
        el = $('.entry:first');
      }
      var reg = /entry([0-9]+)/;
      var matcharray = reg.exec(el.get(0).id);
      var close_id = matcharray[1];
      matcharray = reg.exec(el.nextAll("div").get(0).id);
      var open_id = matcharray[1];
      read(close_id);
      read(open_id);
    }
});
