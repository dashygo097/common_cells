package cc_pkg;
  function automatic int unsigned index_width(input int unsigned count);
    return count > 1 ? $clog2(count) : 1;
  endfunction

endpackage
