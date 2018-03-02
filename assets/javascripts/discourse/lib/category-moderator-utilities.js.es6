const updateCounts = function(user, type, data) {
  let counts = user.get(`${type}_category_counts`);
  counts = counts.filter((c) => c.category_id !== data.category_id);
  counts.push(data);
  user.set(`${type}_category_counts`, counts);

  let total = 0;
  counts.forEach((c) => total += c.count);
  user.set(`${type}_category_counts_total`, total);
};

const typeMap = {
  1: 'admin.user.moderation.type.default',
  2: 'admin.user.moderation.type.filtered'
};

export { updateCounts, typeMap };
